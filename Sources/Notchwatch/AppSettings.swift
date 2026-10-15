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
    /// Además de la isla, una notificación en el Centro de notificaciones de macOS.
    var systemNotifications = true
    /// Atajo global para desplegar o recoger la isla.
    var hotKey: HotKeyChoice = .default
    /// Filtro de la isla desplegada: solo las incidencias asignadas a mí.
    var showOnlyMine = false

    static let storageKey = "notchwatch.settings.v1"

    init() {}

    /// Tolerante a versiones anteriores: lo que falte (o no se entienda) toma su valor por defecto.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pollInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .pollInterval) ?? 20
        enabledProjects = try container.decodeIfPresent([String: Bool].self, forKey: .enabledProjects) ?? [:]
        sound = try container.decodeIfPresent(SoundPolicy.self, forKey: .sound) ?? .default
        preferredScreenID = try container.decodeIfPresent(String.self, forKey: .preferredScreenID)
        expandOnHover = try container.decodeIfPresent(Bool.self, forKey: .expandOnHover) ?? true
        systemNotifications = try container.decodeIfPresent(Bool.self, forKey: .systemNotifications) ?? true
        let hotKeyName = try container.decodeIfPresent(String.self, forKey: .hotKey)
        hotKey = hotKeyName.flatMap(HotKeyChoice.init(rawValue:)) ?? .default
        showOnlyMine = try container.decodeIfPresent(Bool.self, forKey: .showOnlyMine) ?? false
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

/// Atajo global para desplegar o recoger la isla (lo registra `GlobalHotKey`).
enum HotKeyChoice: String, Codable, CaseIterable, Identifiable {
    case off
    case controlOptionCommandI
    case controlOptionCommandN
    case optionCommandI

    /// ⌃⌥⌘I: «I» de incidencias y sin chocar con atajos habituales.
    static let `default`: HotKeyChoice = .controlOptionCommandI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Desactivado"
        case .controlOptionCommandI: return "⌃⌥⌘I"
        case .controlOptionCommandN: return "⌃⌥⌘N"
        case .optionCommandI: return "⌥⌘I"
        }
    }

    /// Aviso cuando el atajo choca con otro muy usado.
    var conflictNote: String? {
        switch self {
        case .optionCommandI:
            return "⌥⌘I también abre las herramientas de desarrollo de Chrome y Safari: mientras Notchwatch lo use, no les llegará."
        default:
            return nil
        }
    }
}
