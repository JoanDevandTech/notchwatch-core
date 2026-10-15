import AppKit
import SwiftUI

/// Panel sin bordes que flota por encima de la barra de menús y nunca roba el foco.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Coloca la isla centrada sobre el notch y decide cuándo el panel acepta el ratón:
/// fuera de la silueta de la isla los clics pasan a la barra de menús.
@MainActor
final class NotchWindowController {
    let panel: NotchPanel
    private let model: AppModel
    private var trackingTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        let panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: IslandLayout.canvas),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        let hosting = NSHostingView(rootView: IslandRootView().environmentObject(model))
        hosting.frame = NSRect(origin: .zero, size: IslandLayout.canvas)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.panel = panel

        model.onLayoutChange = { [weak self] in
            self?.reposition()
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
        reposition()
    }

    func show() {
        panel.orderFrontRegardless()
        startTracking()
    }

    /// Recoloca la ventana en la pantalla elegida (o en la del notch) y actualiza sus medidas.
    func reposition() {
        guard let screen = ScreenLocator.preferredScreen(id: model.settings.preferredScreenID) else { return }
        model.notch = ScreenLocator.metrics(for: screen)
        let size = IslandLayout.canvas
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Sigue el puntero: rápido (25 Hz) cerca de la parte superior de la pantalla y más
    /// despacio (6 Hz) cuando el cursor está lejos, para no gastar batería.
    private func startTracking() {
        trackingTask?.cancel()
        trackingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let near = self.updatePointer()
                try? await Task.sleep(nanoseconds: near ? 40_000_000 : 160_000_000)
            }
        }
    }

    /// Hover de la isla y paso de clics fuera de su silueta. Devuelve si el cursor anda cerca.
    @discardableResult
    private func updatePointer() -> Bool {
        let size = IslandLayout.size(
            for: model.mode,
            notch: model.notch,
            rows: model.listedIncidents.count,
            hasBanner: model.banner != nil
        )
        let frame = panel.frame
        // En reposo, la zona activa es exactamente la píldora (no robar clics a la barra de menús).
        let margin: CGFloat = model.mode == .idle ? 0 : 4
        let island = NSRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        ).insetBy(dx: -margin, dy: -margin)
        let location = NSEvent.mouseLocation
        let inside = island.contains(location)
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        model.setHovering(inside)
        return inside || location.y > frame.maxY - 220
    }
}

/// Elige la pantalla y calcula el tamaño del notch.
@MainActor
enum ScreenLocator {
    static func displayID(of screen: NSScreen) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        return number.stringValue
    }

    static func preferredScreen(id: String?) -> NSScreen? {
        let screens = NSScreen.screens
        if let id, let match = screens.first(where: { displayID(of: $0) == id }) {
            return match
        }
        if let notched = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        return NSScreen.main ?? screens.first
    }

    static func metrics(for screen: NSScreen) -> NotchMetrics {
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return NotchMetrics(notchWidth: max(width, 120), notchHeight: top, hasNotch: true)
        }
        // Sin notch: simulamos uno sobre la barra de menús.
        let menuBar = max(NSStatusBar.system.thickness, 24)
        return NotchMetrics(notchWidth: 180, notchHeight: menuBar + 6, hasNotch: false)
    }
}
