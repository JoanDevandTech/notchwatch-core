import Foundation

/// Orquestador sin UI: hace poll de todos los proyectos enabled en paralelo, aplica diff, persiste y emite resultados.
///
/// Reglas:
/// - `PollOutcome.newIncidents` solo trae lo que hay que avisar: cada incidencia se emite una vez por
///   sesión (y otra vez cuando vence su snooze). `pending` trae todas las abiertas no vistas.
/// - Línea base por proyecto: la primera vez que un proyecto responde (o al reactivarlo) sus incidencias
///   con más de 10 min se dan por vistas y solo se avisan las recientes. Así un proyecto que falla en el
///   primer arranque, o que se reactiva en Ajustes, no inunda de avisos al volver.
/// - Si un proyecto falla, se usa su última lista conocida; si no la hay, no se borra el estado
///   (vistas/pospuestas) de sus incidencias.
public actor IncidentMonitor {
    /// Antigüedad a partir de la cual una incidencia ya existente no se avisa al tomar la línea base.
    static let freshWindow: TimeInterval = 600

    private typealias FetchResult = Result<[Incident], AsanaError>

    private var client: AsanaClient
    private var config: NotchwatchConfig
    private let storeURL: URL
    private let clock: @Sendable () -> Date
    private var store: SeenStore
    /// GIDs ya emitidos como nuevos en esta sesión (evita repetir el aviso en cada poll).
    private var notified: Set<String> = []
    /// Última lista correcta por proyecto, para no perder estado si un proyecto falla.
    private var lastKnown: [String: [Incident]] = [:]

    public init(
        client: AsanaClient,
        config: NotchwatchConfig,
        storeURL: URL,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.config = config
        self.storeURL = storeURL
        self.clock = now
        self.store = SeenStore.load(from: storeURL) ?? SeenStore()
    }

    /// Consulta todos los proyectos activos. Nunca lanza: los errores van en `outcome.errors`.
    public func poll() async -> PollOutcome {
        let projects = config.projects.filter { $0.enabled }
        // Sin proyectos activos no se consulta nada ni se toca el estado guardado.
        guard !projects.isEmpty else {
            return PollOutcome(newIncidents: [], pending: [], errors: [:], date: clock())
        }

        let results = await IncidentMonitor.fetch(projects, using: client)

        // La config puede haber cambiado durante el await (reentrada del actor).
        let enabledNow = Set(config.projects.filter { $0.enabled }.map { $0.key })
        let date = clock()
        var current: [Incident] = []
        var errors: [String: AsanaError] = [:]
        var hasUnknownProjects = false

        // Se recorren en el orden de la configuración para que el resultado sea determinista.
        for project in projects {
            guard let result = results[project.key] else {
                hasUnknownProjects = true
                continue
            }
            switch result {
            case .success(let incidents):
                if enabledNow.contains(project.key) {
                    lastKnown[project.key] = incidents
                }
                takeBaselineIfNeeded(for: project.key, incidents: incidents, now: date)
                current.append(contentsOf: incidents)
            case .failure(let error):
                errors[project.key] = error
                if let cached = lastKnown[project.key] {
                    current.append(contentsOf: cached)
                } else {
                    hasUnknownProjects = true
                }
            }
        }
        // Un proyecto desactivado pierde su línea base: si se reactiva, se toma otra.
        store.baselinedProjects.formIntersection(enabledNow)

        let previous = store
        let diff = IncidentDiffer.diff(
            current: current,
            store: &store,
            now: date,
            freshWindow: IncidentMonitor.freshWindow
        )
        let openIds = Set(current.map { $0.gid })

        if hasUnknownProjects {
            // Hay proyectos sin datos: no se purga el estado de incidencias que podrían seguir abiertas.
            store.seen.formUnion(previous.seen)
            for (gid, until) in previous.snoozedUntil where !openIds.contains(gid) {
                store.snoozedUntil[gid] = until
            }
        } else {
            notified.formIntersection(openIds)
        }

        // Solo se emiten como nuevas las que no se han avisado ya en esta sesión.
        let fresh = diff.newIncidents.filter { !notified.contains($0.gid) }
        notified.formUnion(fresh.map { $0.gid })

        persist()
        return PollOutcome(newIncidents: fresh, pending: diff.pending, errors: errors, date: date)
    }

    /// Marca una incidencia como vista (deja de estar pendiente).
    public func markSeen(_ gid: String) async {
        store.seen.insert(gid)
        store.snoozedUntil[gid] = nil
        persist()
    }

    /// Pospone una incidencia; al vencer se vuelve a avisar.
    public func snooze(_ gid: String, for duration: TimeInterval) async {
        store.snoozedUntil[gid] = clock().addingTimeInterval(duration)
        notified.remove(gid)
        persist()
    }

    /// Sustituye la configuración (proyectos activos, intervalo, etc.).
    /// Usar esto (y no recrear el monitor) al cambiar los toggles: conserva los avisos ya emitidos.
    public func updateConfig(_ config: NotchwatchConfig) async {
        self.config = config
        let enabledKeys = Set(config.projects.filter { $0.enabled }.map { $0.key })
        lastKnown = lastKnown.filter { enabledKeys.contains($0.key) }
    }

    /// Sustituye el cliente (p. ej. al cambiar el token) conservando vistas, pospuestas y avisos emitidos.
    public func updateClient(_ client: AsanaClient) async {
        self.client = client
        // La caché era de la credencial anterior.
        lastKnown.removeAll()
    }

    // MARK: - Privado

    /// Consulta los proyectos en paralelo; cada uno devuelve su propio `Result`.
    private static func fetch(
        _ projects: [WatchedProject],
        using client: AsanaClient
    ) async -> [String: FetchResult] {
        await withTaskGroup(
            of: (String, FetchResult).self,
            returning: [String: FetchResult].self
        ) { group in
            for project in projects {
                group.addTask {
                    do {
                        let incidents = try await client.openIncidents(in: project)
                        return (project.key, FetchResult.success(incidents))
                    } catch let error as AsanaError {
                        return (project.key, FetchResult.failure(error))
                    } catch {
                        return (project.key, FetchResult.failure(.http(0, error.localizedDescription)))
                    }
                }
            }
            var collected: [String: FetchResult] = [:]
            for await (key, result) in group {
                collected[key] = result
            }
            return collected
        }
    }

    /// Primera respuesta de un proyecto: lo antiguo se da por visto y solo se avisará lo reciente.
    private func takeBaselineIfNeeded(for projectKey: String, incidents: [Incident], now: Date) {
        guard !store.baselinedProjects.contains(projectKey) else { return }
        for incident in incidents where now.timeIntervalSince(incident.createdAt) >= IncidentMonitor.freshWindow {
            store.seen.insert(incident.gid)
        }
        store.baselinedProjects.insert(projectKey)
    }

    /// Guarda el estado en disco (JSON atómico). Un fallo de escritura no interrumpe el poll.
    private func persist() {
        try? store.save(to: storeURL)
    }
}
