import Foundation

/// Cuánto se mueve la isla en reposo.
public enum MotionIntensity: String, Codable, CaseIterable, Sendable {
    case off, subtle, normal, lively

    /// Segundos de pausa entre animaciones ambientales.
    public var ambientInterval: TimeInterval {
        switch self {
        case .off: return 0
        case .subtle: return 16
        case .normal: return 8
        case .lively: return 4
        }
    }
}

/// Atajo global para desplegar o recoger la isla.
public enum HotKeyChoice: String, Codable, CaseIterable, Sendable {
    case off
    case controlOptionCommandI
    case controlOptionCommandN
    case optionCommandI

    public static let `default`: HotKeyChoice = .controlOptionCommandI
}

/// Incidencias de las que avisa la isla. Con `.mine` el contador, la píldora y los avisos solo
/// cuentan las asignadas al usuario del token, y el panel abre filtrado a «Mías».
public enum IncidentScope: String, Codable, CaseIterable, Sendable {
    case mine, all
}

/// Comportamiento: lectura, movimiento, avisos y atajos.
public struct BehaviorSettings: Codable, Equatable, Sendable {
    /// Segundos entre lecturas de las fuentes.
    public var pollInterval: TimeInterval
    public var motion: MotionIntensity
    public var expandOnHover: Bool
    /// Segundos que la tarjeta de aviso se mantiene sola (las altas y urgentes esperan a que se atiendan).
    public var alertDuration: TimeInterval
    public var systemNotifications: Bool
    public var hotKey: HotKeyChoice
    /// Ausente en perfiles antiguos: `.mine`.
    public var scope: IncidentScope
    /// Pantalla elegida; nil = la que tenga notch o la principal.
    public var preferredScreenID: String?

    public init(
        pollInterval: TimeInterval = 20,
        motion: MotionIntensity = .normal,
        expandOnHover: Bool = true,
        alertDuration: TimeInterval = 8,
        systemNotifications: Bool = true,
        hotKey: HotKeyChoice = .default,
        scope: IncidentScope = .mine,
        preferredScreenID: String? = nil
    ) {
        self.pollInterval = pollInterval
        self.motion = motion
        self.expandOnHover = expandOnHover
        self.alertDuration = alertDuration
        self.systemNotifications = systemNotifications
        self.hotKey = hotKey
        self.scope = scope
        self.preferredScreenID = preferredScreenID
    }

    public static let `default` = BehaviorSettings()

    private enum CodingKeys: String, CodingKey {
        case pollInterval, motion, expandOnHover, alertDuration, systemNotifications, hotKey, scope, preferredScreenID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pollInterval = max(try container.decodeIfPresent(TimeInterval.self, forKey: .pollInterval) ?? 20, 10)
        motion = try container.decodeIfPresent(MotionIntensity.self, forKey: .motion) ?? .normal
        expandOnHover = try container.decodeIfPresent(Bool.self, forKey: .expandOnHover) ?? true
        alertDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .alertDuration) ?? 8
        systemNotifications = try container.decodeIfPresent(Bool.self, forKey: .systemNotifications) ?? true
        hotKey = try container.decodeIfPresent(HotKeyChoice.self, forKey: .hotKey) ?? .default
        scope = try container.decodeIfPresent(IncidentScope.self, forKey: .scope) ?? .mine
        preferredScreenID = try container.decodeIfPresent(String.self, forKey: .preferredScreenID)
    }
}
