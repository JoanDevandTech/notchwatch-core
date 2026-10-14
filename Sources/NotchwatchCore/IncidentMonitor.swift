import Foundation

/// Orquestador sin UI: hace poll de todas las colecciones activas de todas las fuentes en paralelo,
/// aplica el diff, persiste y emite resultados.
///
/// Reglas:
/// - `PollOutcome.newIncidents` solo trae lo que hay que avisar: cada incidencia se emite una vez por
///   sesión (y otra vez cuando vence su snooze). `pending` trae todas las abiertas no vistas.
/// - Línea base por colección: la primera vez que una colección responde (o al reactivarla) sus
///   incidencias con más de 10 min se dan por vistas y solo se avisan las recientes. Así una colección
///   que falla en el primer arranque, o que se reactiva en Ajustes, no inunda de avisos al volver.
/// - Si una colección falla, se usa su última lista conocida; si no la hay, no se borra el estado
///   (vistas/pospuestas) de sus incidencias.
public actor IncidentMonitor {
    /// Antigüedad a partir de la cual una incidencia ya existente no se avisa al tomar la línea base.
    public static let freshWindow: TimeInterval = 600

    private typealias FetchResult = Result<[Incident], SourceError>

    /// Colección a consultar junto con la fuente que la sirve.
    private struct Target: Sendable {
        let source: any IncidentSource
        let collection: WatchedCollection
    }

    private var sources: [any IncidentSource]
    private let storeURL: URL
    private let clock: @Sendable () -> Date
    private var store: SeenStore
    /// Incidencias ya emitidas como nuevas en esta sesión (evita repetir el aviso en cada poll).
    private var notified: Set<String> = []
    /// Última lista correcta por colección, para no perder estado si una colección falla.
    private var lastKnown: [String: [Incident]] = [:]

    public init(
        sources: [any IncidentSource],
        storeURL: URL,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sources = sources
        self.storeURL = storeURL
        self.clock = now
        self.store = SeenStore.load(from: storeURL) ?? SeenStore()
    }

    /// Consulta todas las colecciones activas. Nunca lanza: los errores van en `outcome.errors`.
    public func poll() async -> PollOutcome {
        let targets = enabledTargets()
        // Sin colecciones activas no se consulta nada ni se toca el estado guardado.
        guard !targets.isEmpty else {
            return PollOutcome(newIncidents: [], pending: [], errors: [:], date: clock())
        }

        let results = await IncidentMonitor.fetch(targets)

        // Las fuentes pueden haber cambiado durante el await (reentrada del actor).
        let enabledNow = Set(enabledTargets().map { $0.collection.id })
        let date = clock()
        var current: [Incident] = []
        var errors: [String: SourceError] = [:]
        var hasUnknownCollections = false

        // Se recorren en el orden de configuración para que el resultado sea determinista.
        for target in targets {
            let collectionID = target.collection.id
            guard let result = results[collectionID] else {
                hasUnknownCollections = true
                continue
            }
            switch result {
            case .success(let incidents):
                if enabledNow.contains(collectionID) {
                    lastKnown[collectionID] = incidents
                }
                takeBaselineIfNeeded(for: collectionID, incidents: incidents, now: date)
                current.append(contentsOf: incidents)
            case .failure(let error):
                errors[collectionID] = error
                if let cached = lastKnown[collectionID] {
                    current.append(contentsOf: cached)
                } else {
                    hasUnknownCollections = true
                }
            }
        }
        // Una colección desactivada pierde su línea base: si se reactiva, se toma otra.
        store.baselinedCollections.formIntersection(enabledNow)

        let previous = store
        let diff = IncidentDiffer.diff(
            current: current,
            store: &store,
            now: date,
            freshWindow: IncidentMonitor.freshWindow
        )
        let openIDs = Set(current.map { $0.id })

        if hasUnknownCollections {
            // Hay colecciones sin datos: no se purga el estado de incidencias que podrían seguir abiertas.
            store.seen.formUnion(previous.seen)
            for (id, until) in previous.snoozedUntil where !openIDs.contains(id) {
                store.snoozedUntil[id] = until
            }
        } else {
            notified.formIntersection(openIDs)
        }

        // Solo se emiten como nuevas las que no se han avisado ya en esta sesión.
        let fresh = diff.newIncidents.filter { !notified.contains($0.id) }
        notified.formUnion(fresh.map { $0.id })

        persist()
        return PollOutcome(newIncidents: fresh, pending: diff.pending, errors: errors, date: date)
    }

    /// Marca una incidencia como vista (deja de estar pendiente).
    public func markSeen(_ id: String) async {
        store.seen.insert(id)
        store.snoozedUntil[id] = nil
        persist()
    }

    /// Pospone una incidencia; al vencer se vuelve a avisar.
    public func snooze(_ id: String, for duration: TimeInterval) async {
        store.snoozedUntil[id] = clock().addingTimeInterval(duration)
        notified.remove(id)
        persist()
    }

    /// Sustituye las fuentes conservando vistas, pospuestas y avisos emitidos. La caché de una
    /// colección solo sobrevive si sigue activa y la sirve la misma fuente (por `id`).
    public func updateSources(_ sources: [any IncidentSource]) async {
        let previousOwners = IncidentMonitor.owners(of: self.sources)
        self.sources = sources
        let owners = IncidentMonitor.owners(of: sources)
        let enabled = Set(enabledTargets().map { $0.collection.id })
        lastKnown = lastKnown.filter { entry in
            guard enabled.contains(entry.key), let owner = owners[entry.key] else { return false }
            return previousOwners[entry.key] == owner
        }
    }

    // MARK: - Privado

    private func enabledTargets() -> [Target] {
        sources.flatMap { source in
            source.collections
                .filter { $0.enabled }
                .map { Target(source: source, collection: $0) }
        }
    }

    /// Identificador de la fuente que sirve cada colección.
    private static func owners(of sources: [any IncidentSource]) -> [String: String] {
        var owners: [String: String] = [:]
        for source in sources {
            for collection in source.collections {
                owners[collection.id] = source.id
            }
        }
        return owners
    }

    /// Consulta las colecciones en paralelo; cada una devuelve su propio `Result`.
    private static func fetch(_ targets: [Target]) async -> [String: FetchResult] {
        await withTaskGroup(
            of: (String, FetchResult).self,
            returning: [String: FetchResult].self
        ) { group in
            for target in targets {
                group.addTask {
                    let collectionID = target.collection.id
                    do {
                        let incidents = try await target.source.openIncidents(in: target.collection)
                        return (collectionID, FetchResult.success(incidents))
                    } catch let error as SourceError {
                        return (collectionID, FetchResult.failure(error))
                    } catch {
                        return (collectionID, FetchResult.failure(.network(error.localizedDescription)))
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

    /// Primera respuesta de una colección: lo antiguo se da por visto y solo se avisará lo reciente.
    private func takeBaselineIfNeeded(for collectionID: String, incidents: [Incident], now: Date) {
        guard !store.baselinedCollections.contains(collectionID) else { return }
        for incident in incidents where now.timeIntervalSince(incident.createdAt) >= IncidentMonitor.freshWindow {
            store.seen.insert(incident.id)
        }
        store.baselinedCollections.insert(collectionID)
    }

    /// Guarda el estado en disco (JSON atómico). Un fallo de escritura no interrumpe el poll.
    private func persist() {
        try? store.save(to: storeURL)
    }
}
