import Foundation

/// Tipos de fuente que Notchwatch sabe consumir.
public enum SourceKind: String, Codable, CaseIterable, Sendable {
    case asana
}

/// Colección vigilada dentro de una fuente (en Asana, un proyecto).
public struct WatchedCollection: Codable, Hashable, Identifiable, Sendable {
    /// Único en toda la app: `"<sourceID>/<clave>"`.
    public var id: String
    /// Nombre corto para la interfaz («Finanzas»).
    public var name: String
    public var enabled: Bool
    public var style: CollectionStyle

    public init(id: String, name: String, enabled: Bool = true, style: CollectionStyle = .default) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.style = style
    }

    public static func makeID(sourceID: String, key: String) -> String {
        "\(sourceID)/\(key)"
    }
}

/// Estilo gráfico de una colección: símbolo SF y color en hexadecimal («#E78580»).
public struct CollectionStyle: Codable, Hashable, Sendable {
    public var symbol: String
    public var colorHex: String

    public init(symbol: String, colorHex: String) {
        self.symbol = symbol
        self.colorHex = colorHex
    }

    public static let `default` = CollectionStyle(symbol: "square.stack.3d.up.fill", colorHex: "#A8B7C8")
}

/// Qué sabe hacer una fuente con sus incidencias.
public struct SourceCapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let assignToMe = SourceCapabilities(rawValue: 1 << 0)
    public static let resolve = SourceCapabilities(rawValue: 1 << 1)
    public static let dueDate = SourceCapabilities(rawValue: 1 << 2)
    public static let priority = SourceCapabilities(rawValue: 1 << 3)
}

/// Acciones sobre una incidencia que ejecuta la fuente. Abrir el enlace lo hace la app.
public enum IncidentAction: Equatable, Sendable {
    case assignToMe
    /// En Asana: mover a la sección de verificación.
    case resolve
    case setDueDate(String?)
    case setPriority(IncidentPriority)

    public var requiredCapability: SourceCapabilities {
        switch self {
        case .assignToMe: return .assignToMe
        case .resolve: return .resolve
        case .setDueDate: return .dueDate
        case .setPriority: return .priority
        }
    }
}

/// Usuario dueño de las credenciales de una fuente.
public struct SourceIdentity: Equatable, Sendable {
    public var userID: String
    public var name: String

    public init(userID: String, name: String) {
        self.userID = userID
        self.name = name
    }
}

/// Fuente de incidencias ya configurada y autenticada. Todas las operaciones son seguras de llamar en
/// paralelo; los errores se expresan siempre como `SourceError`.
public protocol IncidentSource: Sendable {
    var id: String { get }
    var kind: SourceKind { get }
    var displayName: String { get }
    var collections: [WatchedCollection] { get }
    var capabilities: SourceCapabilities { get }

    func identity() async throws -> SourceIdentity
    func openIncidents(in collection: WatchedCollection) async throws -> [Incident]
    func perform(_ action: IncidentAction, on incident: Incident) async throws
}

/// Configuración persistida de una fuente, sin credenciales (esas van al Llavero por `id`).
public enum SourceConfig: Codable, Equatable, Sendable, Identifiable {
    case asana(AsanaSourceConfig)

    public var id: String {
        switch self {
        case .asana(let config): return config.id
        }
    }

    public var kind: SourceKind {
        switch self {
        case .asana: return .asana
        }
    }

    public var displayName: String {
        switch self {
        case .asana(let config): return config.displayName
        }
    }

    public var collections: [WatchedCollection] {
        switch self {
        case .asana(let config): return config.projects.map(\.collection)
        }
    }
}
