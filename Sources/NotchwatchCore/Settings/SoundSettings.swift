import Foundation

/// Motivos sonoros que sintetiza la app. Cada prioridad lleva uno distinto para reconocerla de oído.
public enum SoundMotif: String, Codable, CaseIterable, Sendable {
    /// Dos notas ascendentes, suaves.
    case chime
    /// Una sola nota con cola larga.
    case drop
    /// Tres notas ascendentes, decididas.
    case triad
    /// Dos pulsos graves repetidos.
    case alarm
    /// Nota aguda muy corta.
    case tick
    /// Acorde cálido descendente.
    case glass
}

/// Franja horaria en minutos desde las 00:00; puede cruzar medianoche.
public struct QuietHours: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var startMinute: Int
    public var endMinute: Int

    public init(enabled: Bool = false, startMinute: Int = 22 * 60, endMinute: Int = 8 * 60) {
        self.enabled = enabled
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    /// true si `date` cae dentro de la franja. Inicio == fin es franja vacía.
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
        return minute >= start || minute < end
    }

    static func normalize(_ minute: Int) -> Int {
        let day = 24 * 60
        return ((minute % day) + day) % day
    }
}

/// «No molestar»: manual (hasta una fecha o hasta desactivarlo) y/o programado por horario.
public struct DoNotDisturb: Codable, Equatable, Sendable {
    public enum Manual: Codable, Equatable, Sendable {
        case off
        case until(Date)
        case indefinite
    }

    public var manual: Manual
    public var schedule: QuietHours
    /// Con «No molestar» activo, las urgentes siguen sonando.
    public var urgentBreaksThrough: Bool

    public init(manual: Manual = .off, schedule: QuietHours = QuietHours(), urgentBreaksThrough: Bool = true) {
        self.manual = manual
        self.schedule = schedule
        self.urgentBreaksThrough = urgentBreaksThrough
    }

    public func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        switch manual {
        case .indefinite:
            return true
        case .until(let end) where end > date:
            return true
        default:
            return schedule.contains(date, calendar: calendar)
        }
    }

    /// Fecha en la que termina el modo manual, si tiene fin.
    public var manualEnd: Date? {
        if case .until(let end) = manual { return end }
        return nil
    }
}

/// Qué hacer al llegar una incidencia.
public struct AlertDecision: Equatable, Sendable {
    public var motif: SoundMotif?
    /// Mostrar la tarjeta de aviso (con «No molestar», solo el contador cambia).
    public var showsAlert: Bool
    public var repeats: Bool

    public init(motif: SoundMotif?, showsAlert: Bool, repeats: Bool) {
        self.motif = motif
        self.showsAlert = showsAlert
        self.repeats = repeats
    }

    public static let silent = AlertDecision(motif: nil, showsAlert: false, repeats: false)
}

/// Sonido por prioridad, volumen, silencio y «No molestar».
public struct SoundSettings: Codable, Equatable, Sendable {
    public var muted: Bool
    /// 0…1.
    public var volume: Double
    public var motifs: [IncidentPriority: SoundMotif]
    public var doNotDisturb: DoNotDisturb
    /// Segundos entre repeticiones de alta/urgente mientras no se atienden.
    public var loudRepeatInterval: TimeInterval
    public var repeatsLoud: Bool

    public init(
        muted: Bool = false,
        volume: Double = 0.6,
        motifs: [IncidentPriority: SoundMotif] = SoundSettings.defaultMotifs,
        doNotDisturb: DoNotDisturb = DoNotDisturb(),
        loudRepeatInterval: TimeInterval = 30,
        repeatsLoud: Bool = true
    ) {
        self.muted = muted
        self.volume = volume
        self.motifs = motifs
        self.doNotDisturb = doNotDisturb
        self.loudRepeatInterval = loudRepeatInterval
        self.repeatsLoud = repeatsLoud
    }

    public static let defaultMotifs: [IncidentPriority: SoundMotif] = [
        .urgente: .alarm,
        .alta: .triad,
        .media: .chime,
        .baja: .drop,
        .ninguna: .tick,
    ]

    public static let `default` = SoundSettings()

    public func motif(for priority: IncidentPriority) -> SoundMotif {
        motifs[priority] ?? SoundSettings.defaultMotifs[priority] ?? .chime
    }

    /// Decide sonido, aviso y repetición para una incidencia que acaba de llegar.
    public func decision(for priority: IncidentPriority, at date: Date, calendar: Calendar = .current) -> AlertDecision {
        if doNotDisturb.isActive(at: date, calendar: calendar) {
            guard priority == .urgente, doNotDisturb.urgentBreaksThrough else { return .silent }
            return AlertDecision(motif: muted ? nil : motif(for: priority), showsAlert: true, repeats: !muted && repeatsLoud)
        }
        return AlertDecision(
            motif: muted ? nil : motif(for: priority),
            showsAlert: true,
            repeats: !muted && repeatsLoud && priority.isLoud
        )
    }

    private enum CodingKeys: String, CodingKey {
        case muted, volume, motifs, doNotDisturb, loudRepeatInterval, repeatsLoud
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        muted = try container.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        volume = min(max(try container.decodeIfPresent(Double.self, forKey: .volume) ?? 0.6, 0), 1)
        let custom = try container.decodeIfPresent([IncidentPriority: SoundMotif].self, forKey: .motifs) ?? [:]
        motifs = SoundSettings.defaultMotifs.merging(custom) { _, chosen in chosen }
        doNotDisturb = try container.decodeIfPresent(DoNotDisturb.self, forKey: .doNotDisturb) ?? DoNotDisturb()
        loudRepeatInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .loudRepeatInterval) ?? 30
        repeatsLoud = try container.decodeIfPresent(Bool.self, forKey: .repeatsLoud) ?? true
    }
}
