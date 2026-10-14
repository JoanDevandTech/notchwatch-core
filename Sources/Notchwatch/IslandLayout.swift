import SwiftUI

/// Medidas del notch de la pantalla donde vive la isla.
struct NotchMetrics: Equatable {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var hasNotch: Bool

    static let fallback = NotchMetrics(notchWidth: 190, notchHeight: 32, hasNotch: false)
}

/// Estados visuales de la isla.
enum IslandMode: Equatable {
    /// Píldora mínima pegada al notch: icono de estado a la izquierda y contador a la derecha.
    case idle
    /// Tarjeta que asoma al entrar una incidencia nueva.
    case peek
    /// Panel desplegado con la lista de pendientes y sus acciones.
    case expanded
}

/// Tamaños y radios de cada estado. La vista y el seguimiento del ratón usan exactamente lo mismo.
enum IslandLayout {
    /// Lienzo transparente de la ventana: cabe la isla desplegada más el halo y la sombra.
    static let canvas = CGSize(width: 720, height: 540)
    static let earWidth: CGFloat = 46
    static let rowHeight: CGFloat = 60
    static let rowSpacing: CGFloat = 6
    static let headerHeight: CGFloat = 40
    static let footerHeight: CGFloat = 28
    static let bannerHeight: CGFloat = 34
    static let maxVisibleRows = 5

    static func size(for mode: IslandMode, notch: NotchMetrics, rows: Int, hasBanner: Bool) -> CGSize {
        switch mode {
        case .idle:
            return CGSize(width: notch.notchWidth + earWidth * 2, height: notch.notchHeight)
        case .peek:
            return CGSize(width: max(notch.notchWidth + 250, 470), height: notch.notchHeight + 108)
        case .expanded:
            let visible = CGFloat(min(max(rows, 1), maxVisibleRows))
            let list: CGFloat = rows == 0 ? 96 : visible * rowHeight + (visible - 1) * rowSpacing + 12
            let banner: CGFloat = hasBanner ? bannerHeight : 0
            return CGSize(
                width: max(notch.notchWidth + 360, 580),
                height: notch.notchHeight + headerHeight + list + banner + footerHeight + 10
            )
        }
    }

    /// Radio de los "hombros" cóncavos que funden la isla con el borde superior.
    static func topRadius(for mode: IslandMode) -> CGFloat {
        switch mode {
        case .idle: return 6
        case .peek: return 10
        case .expanded: return 12
        }
    }

    /// Radio de las esquinas inferiores.
    static func bottomRadius(for mode: IslandMode, notch: NotchMetrics) -> CGFloat {
        switch mode {
        case .idle: return max(notch.notchHeight * 0.42, 10)
        case .peek: return 28
        case .expanded: return 32
        }
    }
}

extension Animation {
    /// Muelle principal de la isla: rápido y con un pequeño rebote, como la Dynamic Island.
    static let islandSpring = Animation.spring(response: 0.45, dampingFraction: 0.78)
    /// Muelle corto para micro-interacciones (hover, filas).
    static let islandSnappy = Animation.spring(response: 0.3, dampingFraction: 0.86)
}
