import Foundation

/// Todo lo configurable de Notchwatch, sin credenciales. Es lo que se guarda en disco y lo que se
/// exporta para replicar la instalación en otro Mac.
public struct NotchwatchProfile: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var sources: [SourceConfig]
    public var appearance: AppearanceSettings
    public var sound: SoundSettings
    public var behavior: BehaviorSettings

    public init(
        version: Int = NotchwatchProfile.currentVersion,
        sources: [SourceConfig] = [],
        appearance: AppearanceSettings = .default,
        sound: SoundSettings = .default,
        behavior: BehaviorSettings = .default
    ) {
        self.version = version
        self.sources = sources
        self.appearance = appearance
        self.sound = sound
        self.behavior = behavior
    }

    public static let empty = NotchwatchProfile()

    /// Colecciones de todas las fuentes, en orden.
    public var collections: [WatchedCollection] {
        sources.flatMap(\.collections)
    }

    public func collection(id: String) -> WatchedCollection? {
        collections.first { $0.id == id }
    }

    private enum CodingKeys: String, CodingKey {
        case version, sources, appearance, sound, behavior
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? NotchwatchProfile.currentVersion
        sources = try container.decodeIfPresent([SourceConfig].self, forKey: .sources) ?? []
        appearance = try container.decodeIfPresent(AppearanceSettings.self, forKey: .appearance) ?? .default
        sound = try container.decodeIfPresent(SoundSettings.self, forKey: .sound) ?? .default
        behavior = try container.decodeIfPresent(BehaviorSettings.self, forKey: .behavior) ?? .default
    }
}

public enum ProfileCodec {
    public static func encode(_ profile: NotchwatchProfile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(profile)
    }

    public static func decode(_ data: Data) throws -> NotchwatchProfile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NotchwatchProfile.self, from: data)
    }

    public static func load(from url: URL) -> NotchwatchProfile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }

    public static func save(_ profile: NotchwatchProfile, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(profile).write(to: url, options: .atomic)
    }
}
