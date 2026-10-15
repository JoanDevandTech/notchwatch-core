import Foundation

/// Estado persistente: incidencias ya vistas y pospuestas (JSON en Application Support).
public struct SeenStore: Codable, Sendable {
    /// GIDs marcados como vistos por el usuario (o dados por vistos al tomar la línea base).
    public var seen: Set<String>
    /// GID -> fecha hasta la que está pospuesta.
    public var snoozedUntil: [String: Date]
    /// false hasta la primera ejecución del diff.
    public var initialized: Bool
    /// Claves de proyecto cuya línea base ya se tomó (sus incidencias antiguas se dieron por vistas
    /// la primera vez que respondió). Lo gestiona `IncidentMonitor`; ausente en JSON = vacío.
    public var baselinedProjects: Set<String>

    public init() {
        self.seen = []
        self.snoozedUntil = [:]
        self.initialized = false
        self.baselinedProjects = []
    }

    private enum CodingKeys: String, CodingKey {
        case seen, snoozedUntil, initialized, baselinedProjects
    }

    /// Decodificación tolerante: los campos ausentes toman su valor por defecto.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.seen = try container.decodeIfPresent(Set<String>.self, forKey: .seen) ?? []
        self.snoozedUntil = try container.decodeIfPresent([String: Date].self, forKey: .snoozedUntil) ?? [:]
        self.initialized = try container.decodeIfPresent(Bool.self, forKey: .initialized) ?? false
        self.baselinedProjects = try container.decodeIfPresent(Set<String>.self, forKey: .baselinedProjects) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seen, forKey: .seen)
        try container.encode(snoozedUntil, forKey: .snoozedUntil)
        try container.encode(initialized, forKey: .initialized)
        try container.encode(baselinedProjects, forKey: .baselinedProjects)
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
