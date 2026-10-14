import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    private let arguments: LaunchArguments
    private var model: AppModel?
    private var islandController: NotchWindowController?
    private var statusController: StatusItemController?
    private var settingsController: SettingsWindowController?
    private var datePickerController: DatePickerWindowController?

    init(arguments: LaunchArguments) {
        self.arguments = arguments
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let directory = arguments.snapshotDirectory {
            exit(SnapshotRenderer.renderAll(to: directory))
        }
        if arguments.selfTest {
            runSelfTest()
            return
        }
        launch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func launch() {
        installEditMenu()
        let model = AppModel(demo: arguments.demo)
        let settings = SettingsWindowController(model: model)
        let datePicker = DatePickerWindowController()
        let island = NotchWindowController(model: model)
        let status = StatusItemController(model: model)

        model.onRequestSettings = { [weak settings] in
            settings?.show()
        }
        model.onPickDueDate = { [weak model, weak datePicker] incident in
            datePicker?.show(for: incident) { date in
                model?.setDueDate(incident, to: date)
            }
        }
        status.onOpenSettings = { [weak settings] in
            settings?.show()
        }
        status.onShowIsland = { [weak model] in
            model?.showFromCommand()
        }

        self.model = model
        settingsController = settings
        datePickerController = datePicker
        islandController = island
        statusController = status

        island.show()
        model.start()
    }

    /// Las apps de barra de menús no tienen menú principal: sin un menú Edición (invisible),
    /// ⌘C / ⌘V / ⌘A no llegan a los campos de texto de Ajustes (p. ej. al pegar el token).
    private func installEditMenu() {
        let edit = NSMenu(title: "Edición")
        edit.addItem(withTitle: "Deshacer", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Rehacer", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        let mainMenu = NSMenu()
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    /// Comprueba que la UI se monta sin red ni permisos y sale. Lo usa la CI.
    private func runSelfTest() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            FileHandle.standardError.write(Data("SELF-TEST TIMEOUT\n".utf8))
            exit(3)
        }
        let model = AppModel(demo: true, snapshot: true)
        model.applySnapshot(mode: .expanded, pending: DemoData.initialIncidents(), peek: nil)
        let island = NotchWindowController(model: model)
        island.panel.orderFrontRegardless()
        island.panel.contentView?.layoutSubtreeIfNeeded()
        let settings = NSHostingView(rootView: SettingsView().environmentObject(model))
        settings.layoutSubtreeIfNeeded()
        guard model.sound.prepareBuffers() else {
            FileHandle.standardError.write(Data("SELF-TEST: no se generaron los sonidos\n".utf8))
            exit(2)
        }
        FileHandle.standardOutput.write(Data("SELF-TEST OK\n".utf8))
        exit(0)
    }
}
