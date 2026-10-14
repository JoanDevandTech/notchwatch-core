import Foundation
import NotchwatchCore

/// Preferencias de la app (UserDefaults). El token NO va aquí: vive en el Llavero.
struct AppSettings: Codable, Equatable {
    var pollInterval: TimeInterval = 20
    /// Proyectos desactivados por el usuario (clave de app → activo). Si falta, está activo.
    var enabledProjects: [String: Bool] = [:]
    var sound: SoundPolicy = .default
    /// Pantalla elegida (NSScreenNumber). `nil` = automática (la que tenga notch).
    var preferredScreenID: String?
    var expandOnHover = true

    static let storageKey = "notchwatch.settings.v1"

    init() {}

    /// Tolerante a versiones anteriores: lo que falte toma su valor por defecto.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pollInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .pollInterval) ?? 20
        enabledProjects = try container.decodeIfPresent([String: Bool].self, forKey: .enabledProjects) ?? [:]
        sound = try container.decodeIfPresent(SoundPolicy.self, forKey: .sound) ?? .default
        preferredScreenID = try container.decodeIfPresent(String.self, forKey: .preferredScreenID)
        expandOnHover = try container.decodeIfPresent(Bool.self, forKey: .expandOnHover) ?? true
    }

    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: AppSettings.storageKey)
    }
}
