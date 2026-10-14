import Foundation
import SwiftUI
import NotchwatchCore

// MARK: - Tema por prioridad

extension IncidentPriority {
    /// Color de la prioridad: urgente rojo, alta naranja, media amarillo, baja verde.
    var tint: Color {
        switch self {
        case .urgente: return Color(red: 1.0, green: 0.27, blue: 0.27)
        case .alta: return Color(red: 1.0, green: 0.6, blue: 0.12)
        case .media: return Color(red: 1.0, green: 0.84, blue: 0.2)
        case .baja: return Color(red: 0.25, green: 0.86, blue: 0.45)
        case .ninguna: return Color(white: 0.62)
        }
    }

    var symbol: String {
        switch self {
        case .urgente: return "flame.fill"
        case .alta: return "exclamationmark.triangle.fill"
        case .media: return "exclamationmark.circle.fill"
        case .baja: return "info.circle.fill"
        case .ninguna: return "circle.dashed"
        }
    }

    /// Orden de los menús: de más a menos urgente.
    static let menuOrder: [IncidentPriority] = [.urgente, .alta, .media, .baja, .ninguna]
}

extension Incident {
    /// Nombre corto de la app para los chips ("Ventas" en vez de "Ventas Incidencias").
    var appLabel: String {
        switch projectKey {
        case "ventas": return "Ventas"
        case "finanzas": return "Finanzas"
        case "operaciones": return "Operaciones"
        case "traslados": return "Traslados"
        case "mailing": return "Mailing"
        case "mitbc": return "Mi TBC"
        case "general": return "TBC"
        default: return projectName
        }
    }
}

// MARK: - Piezas pequeñas

/// Píldora con el nombre de la prioridad.
struct PriorityBadge: View {
    let priority: IncidentPriority

    var body: some View {
        Text(priority.label.uppercased())
            .font(.system(size: 9.5, weight: .heavy, design: .rounded))
            .kerning(0.6)
            .foregroundColor(priority == .media ? .black : .white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(priority.tint))
    }
}

/// Chip con el nombre del proyecto/app.
struct ProjectChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.75))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.1)))
    }
}

/// Orbe de la prioridad con brillo; late si la incidencia es urgente.
struct PriorityOrb: View {
    let priority: IncidentPriority
    var size: CGFloat = 36
    var animated = true
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [priority.tint.opacity(0.45), priority.tint.opacity(0.08)],
                        center: .center,
                        startRadius: 2,
                        endRadius: size * 0.6
                    )
                )
            Circle()
                .strokeBorder(priority.tint.opacity(0.6), lineWidth: 1)
            Image(systemName: priority.symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(priority.tint)
        }
        .frame(width: size, height: size)
        .shadow(color: priority.tint.opacity(0.55), radius: pulse ? 12 : 6)
        .scaleEffect(pulse ? 1.07 : 1)
        .onAppear {
            guard animated, priority == .urgente else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

/// Botón redondo de icono para la isla, con resaltado al pasar el ratón.
struct IslandIconButton: View {
    let symbol: String
    let help: String
    var tint: Color = .white
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint.opacity(hovering ? 1 : 0.78))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.17 : 0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
        .animation(.islandSnappy, value: hovering)
    }
}

/// Icono de los menús desplegables de cada fila (posponer, fecha, prioridad).
struct MenuIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(0.8))
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.white.opacity(0.07)))
            .contentShape(Circle())
    }
}

/// Etiqueta compacta (icono pequeño + texto) para metadatos.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
                .font(.system(size: 9, weight: .bold))
            configuration.title
        }
    }
}

/// Línea de metadatos de una incidencia: quién la reporta, módulo, errores de consola y vencimiento.
struct IncidentMetaLine: View {
    let incident: Incident

    var body: some View {
        HStack(spacing: 8) {
            if let reporter = incident.reporter, !reporter.isEmpty {
                Label(reporter, systemImage: "person.fill")
            }
            if let module = incident.module, !module.isEmpty {
                Label(module, systemImage: "square.stack.3d.up.fill")
            }
            if let errors = incident.consoleErrors, errors > 0 {
                Label(errors == 1 ? "1 error" : "\(errors) errores", systemImage: "terminal.fill")
                    .foregroundColor(Color(red: 1, green: 0.47, blue: 0.42))
            }
            if let due = incident.dueOn, let text = Formatters.dueText(due) {
                Label(text, systemImage: "calendar")
            }
        }
        .font(.system(size: 10.5, weight: .medium, design: .rounded))
        .foregroundColor(.white.opacity(0.6))
        .labelStyle(CompactLabelStyle())
        .lineLimit(1)
    }
}

// MARK: - Entorno

private struct SnapshotRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// `true` al renderizar capturas con ImageRenderer: se evitan controles que no sabe pintar (Menu).
    var isSnapshotRender: Bool {
        get { self[SnapshotRenderKey.self] }
        set { self[SnapshotRenderKey.self] = newValue }
    }
}

// MARK: - Efectos

/// Halo animado alrededor de la isla en el color de la prioridad (gradiente angular que gira).
/// En urgentes además late. En las capturas (`isStatic`) se pinta un fotograma fijo.
struct GlowRing: View {
    let shape: NotchShape
    let color: Color
    let pulsing: Bool
    var isStatic = false

    var body: some View {
        if isStatic {
            ring(angle: .degrees(35), intensity: 1)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                let angle = Angle.degrees((seconds * 140).truncatingRemainder(dividingBy: 360))
                let wave = 0.5 + 0.5 * sin(seconds * 5)
                ring(angle: angle, intensity: pulsing ? 0.55 + 0.45 * wave : 1)
            }
        }
    }

    private func ring(angle: Angle, intensity: Double) -> some View {
        let gradient = AngularGradient(
            gradient: Gradient(colors: [
                color,
                color.opacity(0.05),
                color.opacity(0.9),
                color.opacity(0.05),
                color,
            ]),
            center: .center,
            angle: angle
        )
        return shape
            .stroke(gradient, lineWidth: 2.2)
            .shadow(color: color.opacity(0.8 * intensity), radius: 10)
            .shadow(color: color.opacity(0.45 * intensity), radius: 24)
            .opacity(intensity)
    }
}

/// Rebote del icono al llegar una incidencia (`symbolEffect` en macOS 14+, escala en 13).
struct BounceOnChange<Value: Equatable>: ViewModifier {
    let value: Value
    @State private var scaled = false

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.symbolEffect(.bounce, value: value)
        } else {
            content
                .scaleEffect(scaled ? 1.3 : 1)
                .onChange(of: value) { _ in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { scaled = true }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        withAnimation(.islandSpring) { scaled = false }
                    }
                }
        }
    }
}
