import Foundation

// MARK: - Prioridad

/// Prioridad de una incidencia. Orden: urgente > alta > media > baja > ninguna.
public enum IncidentPriority: String, Codable, CaseIterable, Sendable, Comparable {
    case baja, media, alta, urgente, ninguna

    /// De más a menos importante.
    public static let descending: [IncidentPriority] = [.urgente, .alta, .media, .baja, .ninguna]

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

    /// Alta y urgente: sonido insistente que se repite hasta que se atiende.
    public var isLoud: Bool {
        self == .alta || self == .urgente
    }
}

extension IncidentPriority: CodingKeyRepresentable {}

// MARK: - Incidencia

/// Incidencia abierta en una colección de una fuente (en Asana, una tarea en la sección «Detectadas»).
public struct Incident: Codable, Hashable, Identifiable, Sendable {
    /// Identificador en la fuente (GID en Asana). Único dentro de la fuente.
    public let id: String
    /// `WatchedCollection.id` a la que pertenece.
    public var collectionID: String
    /// Nombre corto de la colección para chips y notificaciones («Finanzas»).
    public var collectionName: String
    public var name: String
    public var priority: IncidentPriority
    public var reporter: String?
    public var module: String?
    /// Errores de consola que acompañan al ticket, si se conocen.
    public var consoleErrors: Int?
    public var createdAt: Date
    /// Vencimiento «YYYY-MM-DD».
    public var dueOn: String?
    public var assigneeID: String?
    public var assigneeName: String?
    public var permalinkURL: URL?

    public init(
        id: String,
        collectionID: String,
        collectionName: String,
        name: String,
        priority: IncidentPriority = .ninguna,
        reporter: String? = nil,
        module: String? = nil,
        consoleErrors: Int? = nil,
        createdAt: Date,
        dueOn: String? = nil,
        assigneeID: String? = nil,
        assigneeName: String? = nil,
        permalinkURL: URL? = nil
    ) {
        self.id = id
        self.collectionID = collectionID
        self.collectionName = collectionName
        self.name = name
        self.priority = priority
        self.reporter = reporter
        self.module = module
        self.consoleErrors = consoleErrors
        self.createdAt = createdAt
        self.dueOn = dueOn
        self.assigneeID = assigneeID
        self.assigneeName = assigneeName
        self.permalinkURL = permalinkURL
    }

    public var assignee: Assignee {
        Assignee(id: assigneeID, name: assigneeName)
    }

    /// true si está asignada al usuario indicado (ver `Assignee.matches`).
    public func isAssigned(toUserID userID: String?, name userName: String?) -> Bool {
        assignee.matches(userID: userID, name: userName)
    }

    public func isAssigned(to user: SourceIdentity) -> Bool {
        assignee.matches(userID: user.userID, name: user.name)
    }
}

// MARK: - Responsable

/// Responsable de una incidencia tal como lo da la fuente; sin datos, sin asignar.
public struct Assignee: Codable, Hashable, Sendable {
    public var id: String?
    public var name: String?

    public init(id: String? = nil, name: String? = nil) {
        self.id = id
        self.name = name
    }

    /// Si se conocen los dos identificadores deciden ellos (dos personas pueden llamarse igual);
    /// si no, se comparan los nombres sin distinguir mayúsculas.
    public func matches(userID: String?, name userName: String?) -> Bool {
        if let assignee = Text.nonEmpty(id), let user = Text.nonEmpty(userID) {
            return assignee == user
        }
        if let assignee = Text.nonEmpty(name), let user = Text.nonEmpty(userName) {
            return assignee.lowercased() == user.lowercased()
        }
        return false
    }

    public func matches(_ user: SourceIdentity) -> Bool {
        matches(userID: user.userID, name: user.name)
    }
}

// MARK: - Errores

/// Errores de cualquier fuente de incidencias.
public enum SourceError: Error, Equatable, Sendable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    /// Sin red o la petición no llegó a completarse.
    case network(String)
    case http(Int, String)
    case decoding(String)
    /// La configuración de la fuente no sirve (falta una sección, un campo, una URL válida…).
    case invalidConfiguration(String)
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
    /// Errores por `WatchedCollection.id`.
    public var errors: [String: SourceError]
    public var date: Date

    public init(newIncidents: [Incident], pending: [Incident], errors: [String: SourceError], date: Date) {
        self.newIncidents = newIncidents
        self.pending = pending
        self.errors = errors
        self.date = date
    }
}

// MARK: - Utilidades

public enum Text {
    /// Recorta espacios y devuelve nil si no queda nada.
    public static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
