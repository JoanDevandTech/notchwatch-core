import Foundation

extension Incident {
    /// Nombre corto de la app para chips y notificaciones ("Ventas" en vez de "Ventas Incidencias").
    /// Si la clave del proyecto no es conocida, devuelve `projectName`.
    public var appLabel: String {
        switch projectKey {
        case "ventas": return "Ventas"
        case "finanzas": return "Finanzas"
        case "operaciones": return "Operaciones"
        case "traslados": return "Traslados"
        case "mailing": return "Mailing"
        case "mitbc": return "Mi TBC"
        case "general": return "TBC"
        default: return projectName
        }
    }

    /// true si la incidencia está asignada al usuario indicado (filtro «Mías»).
    /// Los textos vacíos o solo con espacios cuentan como ausentes. Si se conocen los dos GID, deciden ellos
    /// aunque coincidan los nombres (dos personas pueden llamarse igual); si no, se comparan los nombres
    /// sin espacios en los extremos y sin distinguir mayúsculas. Sin datos comparables, false.
    public func isAssigned(toUserGid userGid: String?, name userName: String?) -> Bool {
        if let assignee = AsanaClient.nonEmpty(assigneeGid), let user = AsanaClient.nonEmpty(userGid) {
            return assignee == user
        }
        if let assignee = AsanaClient.nonEmpty(assigneeName), let user = AsanaClient.nonEmpty(userName) {
            return assignee.lowercased() == user.lowercased()
        }
        return false
    }
}
