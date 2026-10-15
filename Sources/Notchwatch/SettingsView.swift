import AppKit
import Combine
import SwiftUI
import NotchwatchCore

/// Ventana de ajustes (normal, activa la app al abrirse).
@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView().environmentObject(model))
            let window = NSWindow(contentViewController: controller)
            window.title = "Ajustes de Notchwatch"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        AppActivation.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tokenDraft = ""
    @State private var githubDraft = ""
    @State private var testing = false
    @State private var testResult: ConnectionTestResult?
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    private let intervals: [TimeInterval] = [10, 15, 20, 30, 60, 120]
    private let repeatIntervals: [TimeInterval] = [15, 30, 60, 120, 300]

    var body: some View {
        Form {
            asanaSection
            projectsSection
            soundSection
            generalSection
            testSection
            updatesSection
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 720)
        .onAppear { model.refreshNotificationPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Al volver de Ajustes del Sistema, por si cambió el permiso.
            model.refreshNotificationPermission()
        }
    }

    // MARK: Asana

    private var asanaSection: some View {
        Section {
            if model.hasToken && !model.isDemo {
                LabeledContent("Estado") {
                    Label(
                        model.userName.map { "Conectado como \($0)" } ?? "Token guardado",
                        systemImage: "checkmark.seal.fill"
                    )
                    .foregroundColor(.green)
                }
            }
            SecureField("Token personal", text: $tokenDraft, prompt: Text("Pega aquí tu token de Asana"))
            HStack {
                Button(testing ? "Comprobando…" : "Guardar y probar") {
                    saveToken()
                }
                .disabled(testing || tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if model.hasToken && !model.isDemo {
                    Button("Eliminar token", role: .destructive) {
                        model.removeToken()
                        testResult = nil
                    }
                }
                Spacer()
                Link("Crear un token", destination: URL(string: "https://app.asana.com/0/my-apps")!)
            }
            if let testResult {
                switch testResult {
                case .success(let name):
                    Label("Conectado como \(name)", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .failure(let message):
                    Label(message, systemImage: "xmark.octagon.fill")
                        .foregroundColor(.red)
                }
            }
        } header: {
            Text("Conexión con Asana")
        } footer: {
            Text("El token solo se guarda en el Llavero de tu Mac. En Asana: Mi configuración → Apps → Consola de desarrolladores → Token de acceso personal.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func saveToken() {
        let draft = tokenDraft
        testing = true
        Task {
            let result = await model.saveAndTestToken(draft)
            testing = false
            testResult = result
            if case .success = result {
                tokenDraft = ""
            }
        }
    }

    // MARK: Proyectos

    private var projectsSection: some View {
        Section("Proyectos vigilados") {
            ForEach(NotchwatchConfig.tubuencamino.projects) { project in
                Toggle(project.name, isOn: projectBinding(project.key))
            }
        }
    }

    private func projectBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { model.settings.enabledProjects[key] ?? true },
            set: { model.settings.enabledProjects[key] = $0 }
        )
    }

    // MARK: Sonido

    private var soundSection: some View {
        Section("Avisos y sonido") {
            Toggle("Notificación de macOS al entrar una incidencia", isOn: $model.settings.systemNotifications)
            if model.settings.systemNotifications {
                notificationPermissionRow
            }
            Picker("Comprobar Asana cada", selection: $model.settings.pollInterval) {
                ForEach(intervals, id: \.self) { value in
                    Text("\(Int(value)) s").tag(value)
                }
            }
            Toggle("Silenciar todos los sonidos", isOn: $model.settings.sound.muted)
            Picker("Repetir avisos altos/urgentes cada", selection: $model.settings.sound.urgentRepeatInterval) {
                ForEach(repeatIntervals, id: \.self) { value in
                    Text(value < 60 ? "\(Int(value)) s" : "\(Int(value / 60)) min").tag(value)
                }
            }
            Toggle("No molestar (solo suenan las urgentes)", isOn: $model.settings.sound.quietHours.enabled)
            if model.settings.sound.quietHours.enabled {
                Picker("Desde", selection: hourBinding(\.startMinute)) {
                    hourOptions
                }
                Picker("Hasta", selection: hourBinding(\.endMinute)) {
                    hourOptions
                }
            }
            HStack {
                Button("Probar sonido suave") { model.sound.play(.soft) }
                Button("Probar sonido urgente") { model.sound.play(.urgent) }
            }
        }
    }

    @ViewBuilder
    private var notificationPermissionRow: some View {
        switch model.notificationPermission {
        case .allowed:
            EmptyView()
        case .notDetermined:
            HStack {
                Text("macOS todavía no ha dado permiso para notificar.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Pedir permiso") { model.requestNotificationPermission() }
            }
        case .denied:
            HStack {
                Label("macOS tiene bloqueadas las notificaciones de Notchwatch", systemImage: "bell.slash.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Spacer()
                Button("Abrir Ajustes del Sistema") { model.openNotificationSettings() }
            }
        case .unavailable:
            Text("Solo funcionan con Notchwatch.app (no con «swift run»).")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func hourBinding(_ keyPath: WritableKeyPath<QuietHours, Int>) -> Binding<Int> {
        Binding(
            get: { model.settings.sound.quietHours[keyPath: keyPath] / 60 },
            set: { model.settings.sound.quietHours[keyPath: keyPath] = $0 * 60 }
        )
    }

    private var hourOptions: some View {
        ForEach(0..<24, id: \.self) { hour in
            Text(String(format: "%02d:00", hour)).tag(hour)
        }
    }

    // MARK: General

    private var generalSection: some View {
        Section("General") {
            Toggle("Iniciar Notchwatch al arrancar el Mac", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    launchError = LaunchAtLogin.set(newValue)
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
            ))
            if let launchError {
                Text(launchError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            Toggle("Desplegar la isla al pasar el ratón", isOn: $model.settings.expandOnHover)
            Picker("Atajo para mostrar u ocultar la isla", selection: $model.settings.hotKey) {
                ForEach(HotKeyChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            if let hotKeyError = model.hotKeyError {
                Text(hotKeyError)
                    .font(.caption)
                    .foregroundColor(.red)
            } else if let note = model.settings.hotKey.conflictNote {
                Text(note)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            Picker("Pantalla", selection: screenBinding) {
                Text("Automática (la del notch)").tag("auto")
                ForEach(model.availableScreens) { screen in
                    Text(screen.name).tag(screen.id)
                }
            }
        }
    }

    private var screenBinding: Binding<String> {
        Binding(
            get: { model.settings.preferredScreenID ?? "auto" },
            set: { model.settings.preferredScreenID = $0 == "auto" ? nil : $0 }
        )
    }

    // MARK: Pruebas

    private var testSection: some View {
        Section {
            HStack {
                ForEach([IncidentPriority.urgente, .alta, .media, .baja], id: \.self) { priority in
                    Button(priority.label) { model.simulate(priority: priority) }
                }
            }
        } header: {
            Text("Probar la isla")
        } footer: {
            Text("Crea una incidencia de prueba solo en tu Mac, sin tocar Asana.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: Actualizaciones

    private var updatesSection: some View {
        Section {
            SecureField(
                "Token de GitHub",
                text: $githubDraft,
                prompt: Text(model.hasGitHubToken ? "Guardado (pega otro para cambiarlo)" : "Opcional, de solo lectura")
            )
            HStack {
                Button("Guardar token") {
                    model.saveGitHubToken(githubDraft)
                    githubDraft = ""
                }
                .disabled(githubDraft.isEmpty)
                if model.hasGitHubToken {
                    Button("Eliminar", role: .destructive) {
                        model.saveGitHubToken("")
                    }
                }
                Button("Buscar actualizaciones") {
                    Task { await model.checkForUpdates(silent: false) }
                }
                Spacer()
                Text("Versión \(UpdateChecker.currentVersion)")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Actualizaciones")
        } footer: {
            Text("El repositorio es privado: con un token de GitHub de solo lectura la app te avisa de versiones nuevas. Sin token, «Buscar actualizaciones» abre la página de releases.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
