import AppKit
import Combine
import SwiftUI
import NotchwatchCore
import os

/// Estado de una acción lanzada desde una fila (asignar, mover, fecha…).
enum RowActivity: Equatable {
    case working
    case done(String)
    case failed(String)
}

/// Aviso que aparece dentro de la isla desplegada.
struct IslandBanner: Equatable {
    enum Kind: Equatable {
        case warning
        case update
        case info
    }

    var kind: Kind
    var text: String
    var actionTitle: String?
}

enum ConnectionTestResult: Equatable {
    case success(String)
    case failure(String)
}

struct ScreenOption: Identifiable, Hashable {
    let id: String
    let name: String
}

/// Cerebro de la app: hace poll de Asana a través de `IncidentMonitor`, decide qué se avisa
/// (y con qué sonido), gestiona los estados de la isla y ejecuta las acciones rápidas.
@MainActor
final class AppModel: ObservableObject {
    // MARK: - Estado publicado

    @Published private(set) var pending: [Incident] = [] {
        didSet {
            // Lo que deja de estar pendiente (visto, en Verificación, resuelto) sale del Centro de notificaciones.
            let gone = Set(oldValue.map(\.gid)).subtracting(pending.map(\.gid))
            if !gone.isEmpty { notifier?.withdraw(Array(gone)) }
            if pending.isEmpty && !oldValue.isEmpty {
                notifier?.withdraw([NotificationPlanner.summaryIdentifier])
            }
        }
    }
    @Published private(set) var peek: Incident?
    @Published private(set) var peekExtra = 0
    @Published private(set) var mode: IslandMode = .idle
    @Published private(set) var glowPriority: IncidentPriority?
    @Published private(set) var arrivalPulse = 0
    @Published private(set) var connectionIssue: String?
    @Published private(set) var hasToken = false
    @Published private(set) var hasGitHubToken = false
    @Published private(set) var userName: String?
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var activity: [String: RowActivity] = [:]
    @Published private(set) var lastPoll: Date?
    @Published private(set) var update: UpdateInfo?
    @Published private(set) var infoMessage: String?
    @Published private(set) var snoozedUntil: [String: Date] = [:]
    /// GID del usuario del token (para el filtro «Mías»).
    @Published private(set) var userGid: String?
    @Published private(set) var notificationPermission: NotificationPermission = .unavailable
    /// Por qué no se pudo registrar el atajo global (lo enseña Ajustes).
    @Published private(set) var hotKeyError: String?
    @Published var notch: NotchMetrics = .fallback
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            if !isSnapshot { settings.save() }
            settingsChanged(from: oldValue)
        }
    }

    // MARK: - Dependencias y callbacks

    let isDemo: Bool
    let isSnapshot: Bool
    let sound: SoundEngine
    /// Centro de notificaciones de macOS (`nil` fuera de Notchwatch.app y en las capturas).
    let notifier: SystemNotifier?
    var onRequestSettings: (() -> Void)?
    var onPickDueDate: ((Incident) -> Void)?
    var onLayoutChange: (() -> Void)?

    private var client: AsanaClient?
    private var monitor: IncidentMonitor?
    private var config: NotchwatchConfig
    private var pollTask: Task<Void, Never>?
    private var demoTask: Task<Void, Never>?
    private var repeatTask: Task<Void, Never>?
    private var peekTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    private var peekQueue: [Incident] = []
    private var batchExtra = 0
    private var unacknowledgedLoud: Set<String> = []
    private var simulated: Set<String> = []
    private var isFirstPoll = true
    private var isHovering = false
    private var menuTracking = false
    private var expandedByCommand = false
    private var hoveredSinceCommand = false
    private var rateLimitDelay: TimeInterval?
    private var didPromptForSettings = false
    private var observers: [NSObjectProtocol] = []
    /// Token de GitHub en memoria: se lee una vez del Llavero (cada lectura puede pedir permiso).
    private var githubToken: String?
    private var hotKey: GlobalHotKey?
    private var isLoadingUser = false
    /// Clics en notificaciones recibidos antes de la primera lectura de Asana.
    private var deferredResponses: [SystemNotifier.Response] = []
    private let log = Logger(subsystem: "com.joandev.notchwatch", category: "model")

    init(demo: Bool, snapshot: Bool = false) {
        isDemo = demo
        isSnapshot = snapshot
        sound = SoundEngine()
        let loaded = snapshot ? AppSettings() : AppSettings.load()
        settings = loaded
        config = AppModel.makeConfig(from: loaded)
        notifier = snapshot ? nil : SystemNotifier.make()
        if !snapshot {
            githubToken = KeychainStore.read(.githubToken)
            hasGitHubToken = githubToken != nil
            observeMenuTracking()
        }
        if let notifier {
            notificationPermission = .notDetermined
            notifier.onResponse = { [weak self] response in
                self?.handleNotificationResponse(response)
            }
        }
    }

    // MARK: - Derivados para la UI

    var isPaused: Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > Date()
    }

    func isSnoozed(_ incident: Incident, now: Date = Date()) -> Bool {
        guard let until = snoozedUntil[incident.gid] else { return false }
        return until > now
    }

    /// ¿Está asignada al usuario del token? Compara por GID y, si aún no se conoce, por nombre.
    func isMine(_ incident: Incident) -> Bool {
        incident.isAssigned(toUserGid: userGid, name: userName)
    }

    /// Lista de la isla desplegada (con el filtro «Mías» si está activo): primero las activas
    /// y al final las pospuestas.
    var listedIncidents: [Incident] {
        let now = Date()
        let source = settings.showOnlyMine ? pending.filter { isMine($0) } : pending
        let active = source.filter { !isSnoozed($0, now: now) }
        let snoozed = source.filter { isSnoozed($0, now: now) }
        return active + snoozed
    }

    /// Pendientes asignadas a mí (sin contar las pospuestas).
    var mineCount: Int {
        let now = Date()
        return pending.filter { isMine($0) && !isSnoozed($0, now: now) }.count
    }

    /// ¿Sabemos ya quién es el usuario del token? Sin eso el filtro «Mías» no puede decidir.
    var isUserKnown: Bool { userGid != nil || userName != nil }

    /// Pendientes que cuentan para el contador (las pospuestas no).
    var visibleCount: Int {
        let now = Date()
        return pending.filter { !isSnoozed($0, now: now) }.count
    }

    var topPendingPriority: IncidentPriority? {
        let now = Date()
        return pending.filter { !isSnoozed($0, now: now) }.map(\.priority).max()
    }

    var accentPriority: IncidentPriority? { glowPriority ?? topPendingPriority }

    var hasProblem: Bool { (!hasToken && !isDemo) || connectionIssue != nil }

    var statusSymbol: String {
        if !hasToken && !isDemo { return "key.fill" }
        if connectionIssue != nil { return "exclamationmark.triangle.fill" }
        if isPaused { return "bell.slash.fill" }
        if let top = topPendingPriority { return top.symbol }
        return "checkmark.seal.fill"
    }

    var statusTint: Color {
        if hasProblem { return .orange }
        if isPaused { return Color.white.opacity(0.5) }
        if let top = topPendingPriority { return top.tint }
        return Color(red: 0.25, green: 0.86, blue: 0.45)
    }

    var banner: IslandBanner? {
        if !hasToken && !isDemo {
            return IslandBanner(kind: .warning, text: "Falta tu token de Asana", actionTitle: "Configurar")
        }
        if let connectionIssue {
            return IslandBanner(kind: .warning, text: connectionIssue, actionTitle: "Reintentar")
        }
        if let update {
            return IslandBanner(kind: .update, text: "Nueva versión \(update.version) disponible", actionTitle: "Descargar")
        }
        if let infoMessage {
            return IslandBanner(kind: .info, text: infoMessage, actionTitle: nil)
        }
        return nil
    }

    var availableScreens: [ScreenOption] {
        NSScreen.screens.compactMap { screen -> ScreenOption? in
            guard let id = ScreenLocator.displayID(of: screen) else { return nil }
            return ScreenOption(id: id, name: screen.localizedName)
        }
    }

    // MARK: - Arranque

    func start() {
        applyHotKey()
        if settings.systemNotifications {
            requestNotificationPermission()
        } else {
            refreshNotificationPermission()
        }
        if isDemo {
            hasToken = true
            userName = "Modo demo"
            startDemo()
            return
        }
        if let token = KeychainStore.read(.asanaToken), !token.isEmpty {
            configureClient(token: token)
        } else {
            hasToken = false
            requestSettingsOnce()
        }
        Task { [weak self] in
            await self?.checkForUpdates(silent: true)
        }
    }

    static func makeConfig(from settings: AppSettings) -> NotchwatchConfig {
        var config = NotchwatchConfig.tubuencamino
        config.pollInterval = settings.pollInterval
        config.projects = config.projects.map { project in
            var copy = project
            copy.enabled = settings.enabledProjects[project.key] ?? true
            return copy
        }
        return config
    }

    static func storeURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let directory = base.appendingPathComponent("Notchwatch", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("state.json")
    }

    private func configureClient(token: String) {
        let client = AsanaClient(token: token)
        self.client = client
        hasToken = true
        connectionIssue = nil
        if let monitor {
            Task { [weak self] in
                await monitor.updateClient(client)
                self?.startPolling()
            }
        } else {
            monitor = IncidentMonitor(client: client, config: config, storeURL: AppModel.storeURL())
            startPolling()
        }
        loadUser()
    }

    /// Nombre y GID del usuario del token (el GID hace falta para el filtro «Mías»).
    private func loadUser() {
        guard let client, !isLoadingUser else { return }
        isLoadingUser = true
        Task { [weak self] in
            let me = try? await client.me()
            guard let self else { return }
            self.isLoadingUser = false
            // Si el token cambió mientras tanto, el resultado ya no vale.
            guard self.client === client, let me else { return }
            self.userName = me.name
            self.userGid = me.gid
        }
    }

    // MARK: - Poll

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollOnce()
                let delay = self.nextPollDelay()
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private func nextPollDelay() -> TimeInterval {
        let base = max(settings.pollInterval, 10)
        if let rateLimitDelay { return max(base, rateLimitDelay) }
        return base
    }

    func refreshNow() {
        guard !isDemo else { return }
        Task { [weak self] in
            await self?.pollOnce()
        }
    }

    func pollOnce() async {
        guard let monitor, client != nil else { return }
        let outcome = await monitor.poll()
        // El token pudo borrarse mientras se consultaba.
        guard client != nil else { return }
        apply(outcome)
    }

    private func apply(_ outcome: PollOutcome) {
        lastPoll = outcome.date
        let openIDs = Set(outcome.pending.map(\.gid))
        // Las incidencias simuladas desde Ajustes viven solo en local.
        let localOnly = pending.filter { simulated.contains($0.gid) && !openIDs.contains($0.gid) }
        pending = outcome.pending + localOnly
        let keep = Set(pending.map(\.gid))
        if userGid == nil && outcome.errors.isEmpty {
            loadUser()
        }
        snoozedUntil = snoozedUntil.filter { keep.contains($0.key) }
        unacknowledgedLoud = unacknowledgedLoud.filter { keep.contains($0) }
        peekQueue.removeAll { !keep.contains($0.gid) }
        if let current = peek, !keep.contains(current.gid) {
            peekTask?.cancel()
            endPeek()
        }
        updateErrors(outcome.errors)

        let wasFirstPoll = isFirstPoll
        isFirstPoll = false
        if wasFirstPoll && outcome.errors.isEmpty {
            // Notificaciones de sesiones anteriores que ya no corresponden a nada pendiente.
            notifier?.prune(keeping: keep.union([NotificationPlanner.summaryIdentifier]))
        }
        if !outcome.newIncidents.isEmpty {
            announce(outcome.newIncidents, asBatch: wasFirstPoll && outcome.newIncidents.count > 1)
        }
        if unacknowledgedLoud.isEmpty && mode == .idle {
            glowPriority = nil
        }
        if wasFirstPoll && !deferredResponses.isEmpty {
            // Clics en notificaciones que llegaron antes de esta primera lectura.
            let responses = deferredResponses
            deferredResponses.removeAll()
            responses.forEach { handleNotificationResponse($0) }
        }
    }

    private func updateErrors(_ errors: [String: AsanaError]) {
        rateLimitDelay = nil
        guard !errors.isEmpty else {
            connectionIssue = nil
            return
        }
        if errors.values.contains(.unauthorized) {
            connectionIssue = "El token de Asana no es válido o ha caducado"
            requestSettingsOnce()
            return
        }
        for error in errors.values {
            if case .rateLimited(let retryAfter) = error {
                rateLimitDelay = retryAfter ?? 60
            }
        }
        if let rateLimitDelay {
            connectionIssue = "Asana limita las peticiones; reintento en \(Int(rateLimitDelay)) s"
            return
        }
        let offline = errors.values.contains { error in
            if case .http(0, _) = error { return true }
            return false
        }
        if offline {
            connectionIssue = "Sin conexión con Asana"
            return
        }
        let names = errors.keys.sorted().map { key -> String in
            config.projects.first(where: { $0.key == key })?.name ?? key
        }
        connectionIssue = "No se pudo leer: \(names.joined(separator: ", "))"
    }

    // MARK: - Avisos

    private func announce(_ incidents: [Incident], asBatch: Bool) {
        let sorted = incidents.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.createdAt > rhs.createdAt
        }
        guard let top = sorted.first else { return }
        for incident in sorted where incident.priority.isLoud {
            unacknowledgedLoud.insert(incident.gid)
        }
        guard !isPaused else { return }

        // Notificación de macOS (salvo si ya estás mirando la isla desplegada).
        if settings.systemNotifications && !(mode == .expanded && isHovering) {
            notifier?.post(NotificationPlanner.payloads(for: sorted, asBatch: asBatch))
        }

        if asBatch {
            peekQueue = [top]
            batchExtra = sorted.count - 1
        } else {
            peekQueue.append(contentsOf: sorted)
        }
        arrivalPulse &+= 1
        playSound(for: top.priority)
        if mode == .expanded {
            // Ya está desplegada: basta con el halo y el sonido.
            peekQueue.removeAll()
            batchExtra = 0
            if isHovering {
                // La estás mirando: cuenta como atendida, sin repetir el sonido.
                for incident in sorted { unacknowledgedLoud.remove(incident.gid) }
                return
            }
            glowPriority = top.priority
        } else {
            showNextPeekIfPossible()
        }
        scheduleUrgentRepeat()
    }

    private func showNextPeekIfPossible() {
        guard mode != .expanded, peek == nil, !peekQueue.isEmpty else { return }
        let next = peekQueue.removeFirst()
        peek = next
        peekExtra = batchExtra
        batchExtra = 0
        glowPriority = next.priority
        withAnimation(.islandSpring) { mode = .peek }
        peekTask?.cancel()
        // Las altas y urgentes se quedan a la vista hasta que interactúes.
        guard !next.priority.isLoud else { return }
        peekTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            self?.endPeek()
        }
    }

    private func endPeek() {
        peek = nil
        peekExtra = 0
        if !peekQueue.isEmpty {
            showNextPeekIfPossible()
        } else if mode == .peek {
            withAnimation(.islandSpring) { mode = .idle }
            if unacknowledgedLoud.isEmpty { glowPriority = nil }
        }
    }

    private func playSound(for priority: IncidentPriority) {
        guard let kind = settings.sound.sound(for: priority, at: Date()) else { return }
        sound.play(kind)
    }

    /// Repite el sonido de las altas/urgentes hasta que interactúes con la isla.
    private func scheduleUrgentRepeat() {
        guard repeatTask == nil, !unacknowledgedLoud.isEmpty else { return }
        repeatTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = max(self?.settings.sound.urgentRepeatInterval ?? 30, 5)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                let loud = self.pending.filter { self.unacknowledgedLoud.contains($0.gid) }
                guard let top = loud.map(\.priority).max(), !self.isPaused else {
                    self.repeatTask = nil
                    return
                }
                if self.settings.sound.shouldRepeat(for: top) {
                    self.playSound(for: top)
                    self.arrivalPulse &+= 1
                }
            }
        }
    }

    private func acknowledgeAll() {
        unacknowledgedLoud.removeAll()
        glowPriority = nil
        repeatTask?.cancel()
        repeatTask = nil
    }

    private func acknowledge(_ gid: String) {
        unacknowledgedLoud.remove(gid)
        if unacknowledgedLoud.isEmpty {
            repeatTask?.cancel()
            repeatTask = nil
            if mode == .idle { glowPriority = nil }
        }
    }

    // MARK: - Ratón y estados de la isla

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        hoverTask?.cancel()
        if hovering {
            hoveredSinceCommand = true
            if mode == .expanded {
                acknowledgeAll()
                return
            }
            if mode == .peek, let gid = peek?.gid {
                // Pasar el ratón por el aviso lo da por atendido y lo mantiene abierto mientras estés encima.
                acknowledge(gid)
                peekTask?.cancel()
                return
            }
            guard settings.expandOnHover else { return }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                self?.expand()
            }
        } else {
            if mode == .peek, let current = peek, !unacknowledgedLoud.contains(current.gid) {
                peekTask?.cancel()
                peekTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.endPeek()
                }
            }
            scheduleCollapseIfNeeded()
        }
    }

    private func scheduleCollapseIfNeeded() {
        guard mode == .expanded, !isHovering, !menuTracking else { return }
        if expandedByCommand && !hoveredSinceCommand { return }
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let self else { return }
            guard !self.isHovering, !self.menuTracking else { return }
            self.collapse()
        }
    }

    func expand() {
        acknowledgeAll()
        // El resumen del Centro de notificaciones ya no hace falta: estás viendo la lista.
        notifier?.withdraw([NotificationPlanner.summaryIdentifier])
        peekTask?.cancel()
        peekQueue.removeAll()
        batchExtra = 0
        peek = nil
        peekExtra = 0
        withAnimation(.islandSpring) { mode = .expanded }
    }

    func collapse() {
        expandedByCommand = false
        withAnimation(.islandSpring) { mode = .idle }
        if unacknowledgedLoud.isEmpty { glowPriority = nil }
    }

    /// Desplegada desde la barra de menús o con un clic: se cierra al salir el ratón o a los 10 s.
    func showFromCommand() {
        expandedByCommand = true
        hoveredSinceCommand = isHovering
        expand()
        armCommandTimeout(seconds: 10)
    }

    private func armCommandTimeout(seconds: Double) {
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard self.mode == .expanded, !self.isHovering, !self.hoveredSinceCommand else { return }
            if self.menuTracking {
                self.armCommandTimeout(seconds: 2)
            } else {
                self.collapse()
            }
        }
    }

    func islandTapped() {
        if mode != .expanded { showFromCommand() }
    }

    /// Atajo global: despliega la isla o, si ya está desplegada, la recoge.
    func toggleIsland() {
        if mode == .expanded {
            hoverTask?.cancel()
            collapse()
        } else {
            showFromCommand()
        }
    }

    private func observeMenuTracking() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.menuTracking = true }
        })
        observers.append(center.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.menuTracking = false
                self?.scheduleCollapseIfNeeded()
            }
        })
    }

    // MARK: - Acciones rápidas

    func open(_ incident: Incident) {
        acknowledge(incident.gid)
        if isDemo || simulated.contains(incident.gid) {
            flash(incident, "Demo: se abriría en Asana")
            return
        }
        let url = incident.permalinkURL ?? URL(string: "https://app.asana.com/0/0/\(incident.gid)/f")
        if let url { NSWorkspace.shared.open(url) }
    }

    func assignToMe(_ incident: Incident) {
        let name = userName
        let gid = userGid
        applyLocal(incident.gid) {
            $0.assigneeName = name
            $0.assigneeGid = gid
        }
        perform(on: incident, doneMessage: "Asignada a ti") { client, config, _ in
            try await client.assignToMe(incident, config: config)
        }
    }

    func moveToVerification(_ incident: Incident) {
        perform(on: incident, doneMessage: "En verificación", removeAfterSuccess: true) { client, _, project in
            try await client.moveToVerification(incident, project: project)
        }
    }

    func setPriority(_ incident: Incident, to priority: IncidentPriority) {
        applyLocal(incident.gid) { $0.priority = priority }
        perform(on: incident, doneMessage: "Prioridad: \(priority.label)") { client, _, project in
            try await client.setPriority(incident, priority: priority, project: project)
        }
    }

    func setDueDate(_ incident: Incident, to date: Date?) {
        let dueOn = date.map { Formatters.isoDay($0) }
        applyLocal(incident.gid) { $0.dueOn = dueOn }
        perform(on: incident, doneMessage: dueOn == nil ? "Fecha quitada" : "Fecha guardada") { client, _, _ in
            try await client.setDueDate(incident, dueOn: dueOn)
        }
    }

    func setDueDate(_ incident: Incident, option: DueDateOption) {
        setDueDate(incident, to: option.date())
    }

    func pickDueDate(_ incident: Incident) {
        acknowledge(incident.gid)
        onPickDueDate?(incident)
    }

    func snooze(_ incident: Incident, minutes: Int) {
        snooze(incident, until: Date().addingTimeInterval(TimeInterval(minutes * 60)))
    }

    func snoozeUntilTomorrow(_ incident: Incident) {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
            ?? Date().addingTimeInterval(86_400)
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        snooze(incident, until: morning)
    }

    private func snooze(_ incident: Incident, until date: Date) {
        acknowledge(incident.gid)
        snoozedUntil[incident.gid] = date
        flash(incident, "Pospuesta hasta \(Formatters.time(date))")
        guard let monitor, !isDemo, !simulated.contains(incident.gid) else { return }
        let gid = incident.gid
        let duration = max(date.timeIntervalSinceNow, 60)
        Task { await monitor.snooze(gid, for: duration) }
    }

    func markSeen(_ incident: Incident) {
        acknowledge(incident.gid)
        withAnimation(.islandSnappy) {
            pending.removeAll { $0.gid == incident.gid }
        }
        let wasSimulated = simulated.remove(incident.gid) != nil
        guard let monitor, !isDemo, !wasSimulated else { return }
        let gid = incident.gid
        Task { await monitor.markSeen(gid) }
    }

    private func applyLocal(_ gid: String, _ update: (inout Incident) -> Void) {
        guard let index = pending.firstIndex(where: { $0.gid == gid }) else { return }
        var copy = pending[index]
        update(&copy)
        pending[index] = copy
    }

    private func perform(
        on incident: Incident,
        doneMessage: String,
        removeAfterSuccess: Bool = false,
        _ operation: @escaping @Sendable (AsanaClient, NotchwatchConfig, WatchedProject) async throws -> Void
    ) {
        acknowledge(incident.gid)
        if isDemo || simulated.contains(incident.gid) {
            simulateAction(on: incident, doneMessage: doneMessage, removeAfterSuccess: removeAfterSuccess)
            return
        }
        guard let client, let project = config.projects.first(where: { $0.key == incident.projectKey }) else {
            activity[incident.gid] = .failed("Sin conexión con Asana")
            return
        }
        let currentConfig = config
        let gid = incident.gid
        activity[gid] = .working
        Task { [weak self] in
            do {
                try await operation(client, currentConfig, project)
                guard let self else { return }
                self.activity[gid] = .done(doneMessage)
                if removeAfterSuccess {
                    withAnimation(.islandSnappy) {
                        self.pending.removeAll { $0.gid == gid }
                    }
                }
                await self.pollOnce()
            } catch {
                self?.log.error("Acción fallida: \(String(describing: error), privacy: .public)")
                self?.activity[gid] = .failed(AppModel.describe(error))
            }
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            self?.clearActivity(gid)
        }
    }

    private func simulateAction(on incident: Incident, doneMessage: String, removeAfterSuccess: Bool) {
        let gid = incident.gid
        activity[gid] = .working
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self else { return }
            self.activity[gid] = .done(doneMessage)
            if removeAfterSuccess {
                withAnimation(.islandSnappy) {
                    self.pending.removeAll { $0.gid == gid }
                }
                self.simulated.remove(gid)
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.clearActivity(gid)
        }
    }

    private func flash(_ incident: Incident, _ message: String) {
        let gid = incident.gid
        activity[gid] = .done(message)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            self?.clearActivity(gid)
        }
    }

    private func clearActivity(_ gid: String) {
        if case .working? = activity[gid] { return }
        activity[gid] = nil
    }

    static func describe(_ error: Error) -> String {
        guard let asana = error as? AsanaError else { return error.localizedDescription }
        switch asana {
        case .unauthorized:
            return "Token no válido"
        case .rateLimited:
            return "Demasiadas peticiones, prueba en un momento"
        case .http(0, _):
            return "Sin conexión"
        case .http(let code, let message):
            return message.isEmpty ? "Error \(code)" : "Error \(code): \(message)"
        case .decoding:
            return "Respuesta inesperada de Asana"
        case .invalidURL:
            return "URL no válida"
        }
    }

    // MARK: - Pausa

    func togglePause() {
        if isPaused {
            pausedUntil = nil
        } else {
            pause(for: 3_600)
        }
    }

    func pause(for seconds: TimeInterval) {
        pausedUntil = Date().addingTimeInterval(seconds)
        acknowledgeAll()
        peekQueue.removeAll()
        batchExtra = 0
        if mode == .peek {
            peekTask?.cancel()
            endPeek()
        }
    }

    // MARK: - Ajustes y tokens

    func openSettings() {
        onRequestSettings?()
    }

    private func requestSettingsOnce() {
        guard !didPromptForSettings else { return }
        didPromptForSettings = true
        onRequestSettings?()
    }

    func bannerAction() {
        if !hasToken && !isDemo {
            openSettings()
        } else if let issue = connectionIssue {
            if issue.contains("token") { openSettings() } else { refreshNow() }
        } else if let update {
            NSWorkspace.shared.open(update.url)
        }
    }

    func saveAndTestToken(_ raw: String) async -> ConnectionTestResult {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return .failure("Pega tu token personal de Asana.") }
        do {
            let me = try await AsanaClient(token: token).me()
            guard KeychainStore.save(token, account: .asanaToken) else {
                return .failure("No se pudo guardar el token en el Llavero.")
            }
            didPromptForSettings = false
            configureClient(token: token)
            userName = me.name
            userGid = me.gid
            return .success(me.name)
        } catch {
            return .failure(AppModel.describe(error))
        }
    }

    func removeToken() {
        KeychainStore.delete(.asanaToken)
        pollTask?.cancel()
        pollTask = nil
        client = nil
        hasToken = false
        userName = nil
        userGid = nil
        connectionIssue = nil
        acknowledgeAll()
        peekQueue.removeAll()
        batchExtra = 0
        if mode == .peek {
            peekTask?.cancel()
            endPeek()
        }
        withAnimation(.islandSnappy) { pending = [] }
    }

    func saveGitHubToken(_ raw: String) {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            KeychainStore.delete(.githubToken)
            githubToken = nil
            update = nil
        } else {
            KeychainStore.save(token, account: .githubToken)
            githubToken = token
        }
        hasGitHubToken = githubToken != nil
        guard githubToken != nil else { return }
        Task { [weak self] in
            await self?.checkForUpdates(silent: false)
        }
    }

    func checkForUpdates(silent: Bool) async {
        guard let token = githubToken, !token.isEmpty else {
            if !silent { NSWorkspace.shared.open(UpdateChecker.releasesPage) }
            return
        }
        do {
            let found = try await UpdateChecker.latest(token: token)
            update = found
            if found == nil && !silent {
                showInfo("Tienes la última versión (\(UpdateChecker.currentVersion))")
            }
        } catch {
            log.error("Update check: \(String(describing: error), privacy: .public)")
            if !silent { showInfo("No se pudo comprobar si hay actualizaciones") }
        }
    }

    private func showInfo(_ text: String) {
        infoMessage = text
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            self?.infoMessage = nil
        }
    }

    private func settingsChanged(from old: AppSettings) {
        if settings.enabledProjects != old.enabledProjects || settings.pollInterval != old.pollInterval {
            config = AppModel.makeConfig(from: settings)
            if let monitor {
                let newConfig = config
                Task { [weak self] in
                    await monitor.updateConfig(newConfig)
                    await self?.pollOnce()
                }
            }
            if settings.pollInterval != old.pollInterval && pollTask != nil {
                startPolling()
            }
        }
        if settings.preferredScreenID != old.preferredScreenID {
            onLayoutChange?()
        }
        if settings.systemNotifications && !old.systemNotifications {
            requestNotificationPermission()
        } else if !settings.systemNotifications && old.systemNotifications {
            notifier?.withdrawAll()
        }
        if settings.hotKey != old.hotKey {
            applyHotKey()
        }
    }

    // MARK: - Notificaciones de macOS, atajo global y filtro «Mías»

    func requestNotificationPermission() {
        notifier?.requestAuthorization { [weak self] permission in
            self?.notificationPermission = permission
        }
    }

    func refreshNotificationPermission() {
        notifier?.currentPermission { [weak self] permission in
            self?.notificationPermission = permission
        }
    }

    func openNotificationSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.joandev.notchwatch"
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }

    private func applyHotKey() {
        guard !isSnapshot else { return }
        if hotKey == nil {
            hotKey = GlobalHotKey { [weak self] in
                self?.toggleIsland()
            }
        }
        hotKeyError = hotKey?.apply(settings.hotKey)
    }

    /// Selector «Todas / Mías» de la isla desplegada.
    func setShowOnlyMine(_ value: Bool) {
        guard settings.showOnlyMine != value else { return }
        withAnimation(.islandSpring) {
            settings.showOnlyMine = value
        }
    }

    /// Clic en una notificación de macOS o en una de sus acciones.
    private func handleNotificationResponse(_ response: SystemNotifier.Response) {
        let incident = response.incidentGid.flatMap { gid in
            pending.first { $0.gid == gid }
        }
        if incident == nil && response.incidentGid != nil && isFirstPoll && client != nil {
            // Recién arrancada (p. ej. al pulsar una notificación antigua): se atiende tras la primera lectura.
            deferredResponses.append(response)
            return
        }
        switch response.action {
        case SystemNotifier.Action.assign:
            guard let incident else {
                reportNoLongerPending()
                return
            }
            assignToMe(incident)
            showFromCommand()
        case SystemNotifier.Action.snooze:
            guard let incident else {
                reportNoLongerPending()
                return
            }
            snooze(incident, minutes: 60)
            dismissPeek(of: incident.gid)
        default:
            if let incident {
                open(incident)
                dismissPeek(of: incident.gid)
                // En demo y simulaciones no hay tarea que abrir: se enseña la isla.
                if isDemo || simulated.contains(incident.gid) { showFromCommand() }
            } else if let url = response.url {
                NSWorkspace.shared.open(url)
            } else {
                showFromCommand()
            }
        }
    }

    /// Quita de la isla (y de la cola) el aviso de una incidencia atendida desde fuera de ella.
    private func dismissPeek(of gid: String) {
        peekQueue.removeAll { $0.gid == gid }
        if peek?.gid == gid {
            peekTask?.cancel()
            endPeek()
        }
    }

    private func reportNoLongerPending() {
        showInfo("Esa incidencia ya no está pendiente")
        showFromCommand()
    }

    // MARK: - Simulación y demo

    /// Crea una incidencia de prueba solo en local (no toca Asana) para ver la animación.
    func simulate(priority: IncidentPriority) {
        let incident = DemoData.makeIncident(priority: priority)
        simulated.insert(incident.gid)
        withAnimation(.islandSnappy) { pending.insert(incident, at: 0) }
        announce([incident], asBatch: false)
    }

    private func startDemo() {
        pending = DemoData.initialIncidents()
        simulated = Set(pending.map(\.gid))
        lastPoll = Date()
        demoTask?.cancel()
        demoTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if let self {
                self.announce(Array(self.pending.prefix(3)), asBatch: true)
            } else {
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard !Task.isCancelled, let self else { return }
                let incident = DemoData.randomIncident()
                self.simulated.insert(incident.gid)
                withAnimation(.islandSnappy) {
                    self.pending.insert(incident, at: 0)
                    if self.pending.count > 12 {
                        self.simulated.remove(self.pending.removeLast().gid)
                    }
                }
                self.lastPoll = Date()
                self.announce([incident], asBatch: false)
            }
        }
    }

    /// Fija un estado concreto (capturas de CI y self-test). No arranca timers ni red.
    func applySnapshot(
        mode: IslandMode,
        pending: [Incident],
        peek: Incident?,
        notch: NotchMetrics = NotchMetrics(notchWidth: 200, notchHeight: 38, hasNotch: true),
        showOnlyMine: Bool = false
    ) {
        self.notch = notch
        hasToken = true
        userName = "Joan Torres"
        userGid = DemoData.snapshotUserGid
        settings.showOnlyMine = showOnlyMine
        self.pending = pending
        self.peek = peek
        peekExtra = peek == nil ? 0 : 2
        glowPriority = peek?.priority
        lastPoll = Date().addingTimeInterval(-12)
        self.mode = mode
    }
}
