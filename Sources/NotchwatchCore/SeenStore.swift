import Foundation

/// Estado persistente: incidencias ya vistas y pospuestas (JSON en Application Support).
public struct SeenStore: Codable, Sendable {
    /// Identificadores de incidencia marcados como vistos por el usuario (o dados por vistos al tomar la línea base).
    public var seen: Set<String>
    /// Identificador de incidencia -> fecha hasta la que está pospuesta.
    public var snoozedUntil: [String: Date]
    /// false hasta la primera ejecución del diff.
    public var initialized: Bool
    /// Identificadores de colección cuya línea base ya se tomó (sus incidencias antiguas se dieron por vistas
    /// la primera vez que respondió). Lo gestiona `IncidentMonitor`; ausente en JSON = vacío.
    public var baselinedCollections: Set<String>
    /// Último responsable visto de cada incidencia abierta, para detectar reasignaciones. Lo gestiona
    /// `IncidentMonitor`; ausente en JSON = vacío.
    public var assignees: [String: Assignee]

    public init() {
        self.seen = []
        self.snoozedUntil = [:]
        self.initialized = false
        self.baselinedCollections = []
        self.assignees = [:]
    }

    private enum CodingKeys: String, CodingKey {
        case seen, snoozedUntil, initialized, baselinedCollections, assignees
    }

    /// Decodificación tolerante: los campos ausentes toman su valor por defecto.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.seen = try container.decodeIfPresent(Set<String>.self, forKey: .seen) ?? []
        self.snoozedUntil = try container.decodeIfPresent([String: Date].self, forKey: .snoozedUntil) ?? [:]
        self.initialized = try container.decodeIfPresent(Bool.self, forKey: .initialized) ?? false
        self.baselinedCollections = try container.decodeIfPresent(Set<String>.self, forKey: .baselinedCollections) ?? []
        self.assignees = try container.decodeIfPresent([String: Assignee].self, forKey: .assignees) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seen, forKey: .seen)
        try container.encode(snoozedUntil, forKey: .snoozedUntil)
        try container.encode(initialized, forKey: .initialized)
        try container.encode(baselinedCollections, forKey: .baselinedCollections)
        try container.encode(assignees, forKey: .assignees)
    }
}

extension SeenStore {
    /// Codificador con fechas ISO8601 (mismo formato que `makeDecoder`).
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Decodificador con fechas ISO8601 (mismo formato que `makeEncoder`).
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Carga el estado desde disco; nil si no existe o está corrupto.
    static func load(from url: URL) -> SeenStore? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? makeDecoder().decode(SeenStore.self, from: data)
    }

    /// Guarda el estado de forma atómica creando la carpeta si hace falta.
    func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try SeenStore.makeEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }
}
