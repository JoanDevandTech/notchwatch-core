import Foundation

/// Formatos de fecha en español usados por la isla.
enum Formatters {
    /// "ahora", "hace 3 min", "hace 2 h"…
    static func relative(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 45 { return "ahora" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// Hora corta: "17:30" si es hoy, "15 oct 09:00" si no.
    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = calendar.isDateInToday(date) ? "HH:mm" : "d MMM HH:mm"
        return formatter.string(from: date)
    }

    /// Fecha de vencimiento en el formato de Asana ("YYYY-MM-DD") según el calendario local.
    static func isoDay(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    static func parseDay(_ string: String, calendar: Calendar = .current) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// "Vence hoy", "Vence mañana", "Venció ayer", "Vence 21 oct"…
    static func dueText(_ dueOn: String, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let date = parseDay(dueOn, calendar: calendar) else { return nil }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<(-1):
            return "Venció hace \(-days) d"
        case -1:
            return "Venció ayer"
        case 0:
            return "Vence hoy"
        case 1:
            return "Vence mañana"
        case 2...6:
            return "Vence en \(days) d"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es_ES")
            formatter.dateFormat = "d MMM"
            return "Vence \(formatter.string(from: date))"
        }
    }
}

/// Atajos de fecha de vencimiento del menú de cada incidencia.
enum DueDateOption: CaseIterable, Hashable {
    case today
    case tomorrow
    case inThreeDays
    case nextMonday
    case inOneWeek

    var title: String {
        switch self {
        case .today: return "Hoy"
        case .tomorrow: return "Mañana"
        case .inThreeDays: return "En 3 días"
        case .nextMonday: return "Próximo lunes"
        case .inOneWeek: return "En una semana"
        }
    }

    func date(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .today:
            return today
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: today) ?? today
        case .inThreeDays:
            return calendar.date(byAdding: .day, value: 3, to: today) ?? today
        case .inOneWeek:
            return calendar.date(byAdding: .day, value: 7, to: today) ?? today
        case .nextMonday:
            return calendar.nextDate(
                after: today,
                matching: DateComponents(weekday: 2),
                matchingPolicy: .nextTime
            ) ?? today
        }
    }
}
