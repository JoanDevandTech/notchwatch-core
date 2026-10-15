import Foundation

/// Franja horaria de silencio en minutos desde las 00:00 (puede cruzar medianoche).
public struct QuietHours: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Inicio (incluido), minutos desde 00:00.
    public var startMinute: Int
    /// Fin (excluido), minutos desde 00:00.
    public var endMinute: Int

    public init(enabled: Bool = false, startMinute: Int = 22 * 60, endMinute: Int = 8 * 60) {
        self.enabled = enabled
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    /// true si `date` cae dentro de la franja. Inicio == fin se considera franja vacía.
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        let start = QuietHours.normalize(startMinute)
        let end = QuietHours.normalize(endMinute)
        guard start != end else { return false }

        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        if start < end {
            return minute >= start && minute < end
        }
        // Cruza medianoche (p. ej. 22:00–08:00).
        return minute >= start || minute < end
    }

    /// Lleva cualquier valor al rango 0..<1440.
    static func normalize(_ minute: Int) -> Int {
        let day = 24 * 60
        return ((minute % day) + day) % day
    }
}

/// Tipo de sonido a reproducir.
public enum SoundKind: String, Codable, Sendable {
    case soft, urgent
}

/// Reglas de sonido: silencio, horas de silencio y repetición de urgentes.
public struct SoundPolicy: Codable, Equatable, Sendable {
    public var quietHours: QuietHours
    /// Segundos entre repeticiones del aviso alto/urgente.
    public var urgentRepeatInterval: TimeInterval
    public var muted: Bool

    public init(
        quietHours: QuietHours = QuietHours(),
        urgentRepeatInterval: TimeInterval = 30,
        muted: Bool = false
    ) {
        self.quietHours = quietHours
        self.urgentRepeatInterval = urgentRepeatInterval
        self.muted = muted
    }

    /// Política por defecto: sin silencio programado (22:00–08:00 desactivado), repetición cada 30 s.
    public static let `default` = SoundPolicy()

    /// nil si muted o en horas de silencio (urgente SÍ suena en horas de silencio solo si priority == .urgente).
    /// Usa `Calendar.current` para evaluar las horas de silencio.
    public func sound(for priority: IncidentPriority, at date: Date) -> SoundKind? {
        sound(for: priority, at: date, calendar: .current)
    }

    /// Igual que `sound(for:at:)` pero con un calendario explícito (zona horaria fija en tests).
    public func sound(for priority: IncidentPriority, at date: Date, calendar: Calendar) -> SoundKind? {
        if muted { return nil }
        if quietHours.contains(date, calendar: calendar) {
            return priority == .urgente ? .urgent : nil
        }
        return priority.isLoud ? .urgent : .soft
    }

    /// Alta y urgente se repiten hasta que el usuario interactúe (salvo muted).
    public func shouldRepeat(for priority: IncidentPriority) -> Bool {
        priority.isLoud && !muted
    }
}
