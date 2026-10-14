import Foundation

/// Calcula qué incidencias son nuevas y cuáles siguen pendientes respecto al estado persistido.
public enum IncidentDiffer {
    /// Primera ejecución (store.initialized == false): marca todo como visto salvo lo creado hace < `freshWindow` (default 600 s), que se notifica; pone initialized = true.
    /// newIncidents = no vistos y no pospuestos (snooze vencido cuenta como nuevo otra vez), ordenados por prioridad desc y fecha desc.
    /// pending = todas las abiertas no marcadas como vistas (incluye pospuestas), mismo orden. Limpia de `seen`/`snoozedUntil` los gid que ya no están abiertos.
    public static func diff(
        current: [Incident],
        store: inout SeenStore,
        now: Date,
        freshWindow: TimeInterval = 600
    ) -> DiffResult {
        // Quita duplicados (una tarea puede estar en varios proyectos): gana la primera.
        var openIds = Set<String>()
        var unique: [Incident] = []
        for incident in current where !openIds.contains(incident.gid) {
            openIds.insert(incident.gid)
            unique.append(incident)
        }

        // Limpieza de incidencias cerradas o movidas de sección.
        store.seen = store.seen.intersection(openIds)
        store.snoozedUntil = store.snoozedUntil.filter { openIds.contains($0.key) }

        // Primera ejecución: lo antiguo se da por visto para no inundar de avisos.
        if !store.initialized {
            for incident in unique where now.timeIntervalSince(incident.createdAt) >= freshWindow {
                store.seen.insert(incident.gid)
            }
            store.initialized = true
        }

        var newIncidents: [Incident] = []
        var pending: [Incident] = []
        for incident in unique where !store.seen.contains(incident.gid) {
            pending.append(incident)
            if let until = store.snoozedUntil[incident.gid] {
                if until > now {
                    continue // sigue pospuesta
                }
                store.snoozedUntil[incident.gid] = nil // snooze vencido: vuelve a ser nueva
            }
            newIncidents.append(incident)
        }

        return DiffResult(newIncidents: ordered(newIncidents), pending: ordered(pending))
    }

    /// Orden: prioridad desc, fecha de creación desc y gid como desempate estable.
    static func ordered(_ incidents: [Incident]) -> [Incident] {
        incidents.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.gid < rhs.gid
        }
    }
}
