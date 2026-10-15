import Foundation

/// Textos que el núcleo necesita componer (notificaciones). La app los pasa localizados; los tests
/// usan `.spanish`.
public struct NotificationStrings: Sendable {
    public var priorityLabel: @Sendable (IncidentPriority) -> String
    public var reportedBy: @Sendable (String) -> String
    public var consoleErrors: @Sendable (Int) -> String
    public var newIncidents: @Sendable (Int) -> String
    public var pendingIncidents: @Sendable (Int) -> String
    public var mostImportant: @Sendable (String) -> String
    public var andMore: @Sendable (String, Int) -> String

    public init(
        priorityLabel: @escaping @Sendable (IncidentPriority) -> String,
        reportedBy: @escaping @Sendable (String) -> String,
        consoleErrors: @escaping @Sendable (Int) -> String,
        newIncidents: @escaping @Sendable (Int) -> String,
        pendingIncidents: @escaping @Sendable (Int) -> String,
        mostImportant: @escaping @Sendable (String) -> String,
        andMore: @escaping @Sendable (String, Int) -> String
    ) {
        self.priorityLabel = priorityLabel
        self.reportedBy = reportedBy
        self.consoleErrors = consoleErrors
        self.newIncidents = newIncidents
        self.pendingIncidents = pendingIncidents
        self.mostImportant = mostImportant
        self.andMore = andMore
    }

    public static let spanish = NotificationStrings(
        priorityLabel: { priority in
            switch priority {
            case .baja: return "Baja"
            case .media: return "Media"
            case .alta: return "Alta"
            case .urgente: return "Urgente"
            case .ninguna: return "Sin prioridad"
            }
        },
        reportedBy: { "Reportada por \($0)" },
        consoleErrors: { $0 == 1 ? "1 error de consola" : "\($0) errores de consola" },
        newIncidents: { $0 == 1 ? "1 incidencia nueva" : "\($0) incidencias nuevas" },
        pendingIncidents: { $0 == 1 ? "1 incidencia pendiente" : "\($0) incidencias pendientes" },
        mostImportant: { "La más importante: \($0)" },
        andMore: { "\($0) y \($1) más" }
    )
}
