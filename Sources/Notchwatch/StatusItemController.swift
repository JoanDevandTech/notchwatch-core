import AppKit
import Combine

/// Icono en la barra de menús con el contador de pendientes y el menú de la app.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let model: AppModel
    private let pauseItem: NSMenuItem
    private let showItem: NSMenuItem
    private var cancellable: AnyCancellable?
    var onShowIsland: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        pauseItem = NSMenuItem(title: "Pausar avisos 1 h", action: #selector(StatusItemController.togglePause), keyEquivalent: "")
        showItem = NSMenuItem(title: "Mostrar incidencias", action: #selector(StatusItemController.showIsland), keyEquivalent: "i")
        super.init()
        pauseItem.target = self
        showItem.target = self
        statusItem.menu = makeMenu()
        cancellable = model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(showItem)
        menu.addItem(menuItem("Actualizar ahora", #selector(refreshNow), key: "r"))
        menu.addItem(.separator())
        menu.addItem(pauseItem)
        menu.addItem(menuItem("Ajustes…", #selector(openSettings), key: ","))
        menu.addItem(menuItem("Buscar actualizaciones…", #selector(checkUpdates), key: ""))
        menu.addItem(.separator())
        menu.addItem(menuItem("Acerca de Notchwatch", #selector(showAbout), key: ""))
        menu.addItem(menuItem("Salir de Notchwatch", #selector(quit), key: "q"))
        return menu
    }

    private func menuItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func refresh() {
        guard let button = statusItem.button else { return }
        let count = model.visibleCount
        let symbol: String
        if model.hasProblem {
            symbol = "exclamationmark.triangle"
        } else if model.isPaused {
            symbol = "bell.slash"
        } else {
            symbol = count > 0 ? "capsule.fill" : "capsule"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Notchwatch")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.title = count > 0 ? " \(count)" : ""
        button.toolTip = count == 1 ? "1 incidencia pendiente" : "\(count) incidencias pendientes"
        pauseItem.title = model.isPaused ? "Reanudar avisos" : "Pausar avisos 1 h"
        // El atajo global elegido, para que se vea en el menú (nada si está desactivado o falló).
        var shortcut = model.settings.hotKey.menuKeyEquivalent
        if model.hotKeyError != nil { shortcut = ("", []) }
        showItem.keyEquivalent = shortcut.key
        showItem.keyEquivalentModifierMask = shortcut.modifiers
    }

    @objc private func showIsland() {
        onShowIsland?()
    }

    @objc private func refreshNow() {
        model.refreshNow()
    }

    @objc private func togglePause() {
        model.togglePause()
        refresh()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func checkUpdates() {
        let model = self.model
        Task { await model.checkForUpdates(silent: false) }
    }

    @objc private func showAbout() {
        AppActivation.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Notchwatch",
            .applicationVersion: UpdateChecker.currentVersion,
            .credits: NSAttributedString(string: "Incidencias de Tubuencamino en el notch de tu Mac."),
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Trae la app al frente (las apps de barra de menús no se activan solas).
@MainActor
enum AppActivation {
    static func activate() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
