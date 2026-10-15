import Foundation

public enum ThemeMode: String, Codable, CaseIterable, Sendable {
    case automatic, dark, light
}

public enum FontDesignChoice: String, Codable, CaseIterable, Sendable {
    case system, rounded, monospaced
}

public enum TextScale: String, Codable, CaseIterable, Sendable {
    case small, regular, large

    /// Multiplicador sobre los tamaños base de la isla.
    public var factor: Double {
        switch self {
        case .small: return 0.92
        case .regular: return 1
        case .large: return 1.1
        }
    }
}

/// Tema, colores de prioridad y tipografía. Los colores van en hexadecimal («#RRGGBB»).
public struct AppearanceSettings: Codable, Equatable, Sendable {
    public var theme: ThemeMode
    public var priorityColors: [IncidentPriority: String]
    public var fontDesign: FontDesignChoice
    public var textScale: TextScale

    public init(
        theme: ThemeMode = .automatic,
        priorityColors: [IncidentPriority: String] = AppearanceSettings.defaultPriorityColors,
        fontDesign: FontDesignChoice = .system,
        textScale: TextScale = .regular
    ) {
        self.theme = theme
        self.priorityColors = priorityColors
        self.fontDesign = fontDesign
        self.textScale = textScale
    }

    /// Paleta de la isla: rosa, ámbar, sol, salvia y gris.
    public static let defaultPriorityColors: [IncidentPriority: String] = [
        .urgente: "#E78580",
        .alta: "#DFB47D",
        .media: "#D8C790",
        .baja: "#85BAA8",
        .ninguna: "#A8B7C8",
    ]

    public static let `default` = AppearanceSettings()

    public func color(for priority: IncidentPriority) -> String {
        priorityColors[priority] ?? AppearanceSettings.defaultPriorityColors[priority] ?? "#A8B7C8"
    }

    private enum CodingKeys: String, CodingKey {
        case theme, priorityColors, fontDesign, textScale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(ThemeMode.self, forKey: .theme) ?? .automatic
        let colors = try container.decodeIfPresent([IncidentPriority: String].self, forKey: .priorityColors) ?? [:]
        priorityColors = AppearanceSettings.defaultPriorityColors.merging(colors) { _, custom in custom }
        fontDesign = try container.decodeIfPresent(FontDesignChoice.self, forKey: .fontDesign) ?? .system
        textScale = try container.decodeIfPresent(TextScale.self, forKey: .textScale) ?? .regular
    }
}
