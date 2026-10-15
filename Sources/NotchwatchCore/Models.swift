import Foundation

// MARK: - Prioridad

/// Prioridad de una incidencia. Orden: urgente > alta > media > baja > ninguna.
public enum IncidentPriority: String, Codable, CaseIterable, Sendable, Comparable {
    case baja, media, alta, urgente, ninguna

    /// Peso numérico usado para ordenar.
    var rank: Int {
        switch self {
        case .ninguna: return 0
        case .baja: return 1
        case .media: return 2
        case .alta: return 3
        case .urgente: return 4
        }
    }

    public static func < (lhs: IncidentPriority, rhs: IncidentPriority) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Etiqueta en español para la UI.
    public var label: String {
        switch self {
        case .baja: return "Baja"
        case .media: return "Media"
        case .alta: return "Alta"
        case .urgente: return "Urgente"
        case .ninguna: return "Sin prioridad"
        }
    }

    /// Las prioridades "ruidosas" (alta y urgente) usan sonido urgente y se repiten.
    public var isLoud: Bool {
        self == .alta || self == .urgente
    }
}

/// Permite que `[IncidentPriority: String]` se codifique como objeto JSON
/// (`{"alta": "…"}`) en lugar de como array plano clave/valor.
extension IncidentPriority: CodingKeyRepresentable {}

// MARK: - Configuración de proyecto

/// GIDs de las secciones del tablero de incidencias de un proyecto.
public struct ProjectSections: Codable, Hashable, Sendable {
    public var features: String
    public var detectadas: String
    public var verificacion: String
    public var solucion: String
    public var validacion: String
    public var seguimientoInicial: String
    public var seguimientoSemana: String
    public var historico: String

    public init(
        features: String,
        detectadas: String,
        verificacion: String,
        solucion: String,
        validacion: String,
        seguimientoInicial: String,
        seguimientoSemana: String,
        historico: String
    ) {
        self.features = features
        self.detectadas = detectadas
        self.verificacion = verificacion
        self.solucion = solucion
        self.validacion = validacion
        self.seguimientoInicial = seguimientoInicial
        self.seguimientoSemana = seguimientoSemana
        self.historico = historico
    }
}

/// Campo personalizado (enum) de prioridad de un proyecto y sus opciones.
public struct PriorityField: Codable, Hashable, Sendable {
    public var fieldGid: String
    /// prioridad -> GID de la enum_option en Asana.
    public var options: [IncidentPriority: String]

    public init(fieldGid: String, options: [IncidentPriority: String]) {
        self.fieldGid = fieldGid
        self.options = options
    }

    /// Traduce el GID de la opción seleccionada a prioridad (`.ninguna` si no hay o no se reconoce).
    public func priority(forOptionGid gid: String?) -> IncidentPriority {
        guard let gid, !gid.isEmpty else { return .ninguna }
        // Recorremos en orden fijo para que el resultado sea determinista.
        for priority in IncidentPriority.allCases where options[priority] == gid {
            return priority
        }
        return .ninguna
    }
}

/// Proyecto de Asana vigilado.
public struct WatchedProject: Codable, Hashable, Identifiable, Sendable {
    public var id: String { key }
    /// Clave estable: "ventas", "finanzas", "operaciones", "traslados", "mailing", "mitbc", "general".
    public var key: String
    public var name: String
    public var projectGid: String
    public var sections: ProjectSections
    public var priorityField: PriorityField
    public var enabled: Bool

    public init(
        key: String,
        name: String,
        projectGid: String,
        sections: ProjectSections,
        priorityField: PriorityField,
        enabled: Bool = true
    ) {
        self.key = key
        self.name = name
        self.projectGid = projectGid
        self.sections = sections
        self.priorityField = priorityField
        self.enabled = enabled
    }
}

// MARK: - Incidencia

/// Incidencia abierta (tarea de Asana en la sección "detectadas").
public struct Incident: Codable, Hashable, Identifiable, Sendable {
    public var id: String { gid }
    public let gid: String
    public var projectKey: String
    public var projectName: String
    public var name: String
    public var priority: IncidentPriority
    /// Campo personalizado "Reportado por".
    public var reporter: String?
    /// Campo personalizado "Módulo".
    public var module: String?
    /// X de "Errores consola: X/Y" en las notas.
    public var consoleErrors: Int?
    public var createdAt: Date
    /// Fecha de vencimiento "YYYY-MM-DD".
    public var dueOn: String?
    public var assigneeName: String?
    public var permalinkURL: URL?
    /// GID del usuario asignado (para el filtro «Mías»).
    public var assigneeGid: String?

    public init(
        gid: String,
        projectKey: String,
        projectName: String,
        name: String,
        priority: IncidentPriority = .ninguna,
        reporter: String? = nil,
        module: String? = nil,
        consoleErrors: Int? = nil,
        createdAt: Date,
        dueOn: String? = nil,
        assigneeName: String? = nil,
        permalinkURL: URL? = nil,
        assigneeGid: String? = nil
    ) {
        self.gid = gid
        self.projectKey = projectKey
        self.projectName = projectName
        self.name = name
        self.priority = priority
        self.reporter = reporter
        self.module = module
        self.consoleErrors = consoleErrors
        self.createdAt = createdAt
        self.dueOn = dueOn
        self.assigneeName = assigneeName
        self.permalinkURL = permalinkURL
        self.assigneeGid = assigneeGid
    }
}

// MARK: - Errores

/// Errores del cliente de Asana.
public enum AsanaError: Error, Equatable, Sendable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case http(Int, String)
    case decoding(String)
    case invalidURL
}

// MARK: - Resultados

/// Resultado de comparar las incidencias abiertas con el estado persistido.
public struct DiffResult: Equatable, Sendable {
    public var newIncidents: [Incident]
    public var pending: [Incident]

    public init(newIncidents: [Incident], pending: [Incident]) {
        self.newIncidents = newIncidents
        self.pending = pending
    }
}

/// Resultado de un ciclo de poll del monitor.
public struct PollOutcome: Sendable {
    public var newIncidents: [Incident]
    public var pending: [Incident]
    /// Errores por clave de proyecto.
    public var errors: [String: AsanaError]
    public var date: Date

    public init(newIncidents: [Incident], pending: [Incident], errors: [String: AsanaError], date: Date) {
        self.newIncidents = newIncidents
        self.pending = pending
        self.errors = errors
        self.date = date
    }
}
