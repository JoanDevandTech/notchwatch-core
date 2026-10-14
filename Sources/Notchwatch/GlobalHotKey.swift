import AppKit
import Carbon.HIToolbox
import os

/// Firma de los atajos de Notchwatch ("NWCH"): así reconocemos nuestros eventos.
private let hotKeySignature: OSType = 0x4E57_4348

/// Callback de Carbon. Llega en el hilo principal y no puede capturar contexto.
private func handleHotKeyEvent(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == hotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }
    Task { @MainActor in
        GlobalHotKey.fire()
    }
    return noErr
}

/// Atajo de teclado global con `RegisterEventHotKey` (Carbon): funciona con cualquier app
/// delante y no necesita permisos de Accesibilidad ni de monitorización de teclado.
@MainActor
final class GlobalHotKey {
    private static weak var active: GlobalHotKey?

    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let log = Logger(subsystem: "com.joandev.notchwatch", category: "hotkey")

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    /// Registra el atajo elegido (o lo quita con `.off`). Devuelve un mensaje si no se pudo.
    @discardableResult
    func apply(_ choice: HotKeyChoice) -> String? {
        unregister()
        guard let combo = choice.combo else { return nil }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            handleHotKeyEvent,
            1,
            &eventType,
            nil,
            &handlerRef
        )
        guard installed == noErr else {
            log.error("InstallEventHandler: \(installed)")
            return "No se pudo activar el atajo (error \(installed))."
        }

        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: 1)
        let registered = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registered == noErr else {
            log.error("RegisterEventHotKey: \(registered)")
            unregister()
            if registered == OSStatus(eventHotKeyExistsErr) {
                return "Otra app ya usa \(choice.title). Elige otro atajo."
            }
            return "No se pudo activar \(choice.title) (error \(registered))."
        }
        GlobalHotKey.active = self
        return nil
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        if GlobalHotKey.active === self {
            GlobalHotKey.active = nil
        }
    }

    fileprivate static func fire() {
        active?.action()
    }
}

extension HotKeyChoice {
    struct Combo {
        let keyCode: UInt32
        let modifiers: UInt32
    }

    /// Tecla y modificadores en formato Carbon.
    var combo: Combo? {
        let controlOptionCommand = UInt32(controlKey | optionKey | cmdKey)
        switch self {
        case .off:
            return nil
        case .controlOptionCommandI:
            return Combo(keyCode: UInt32(kVK_ANSI_I), modifiers: controlOptionCommand)
        case .controlOptionCommandN:
            return Combo(keyCode: UInt32(kVK_ANSI_N), modifiers: controlOptionCommand)
        case .optionCommandI:
            return Combo(keyCode: UInt32(kVK_ANSI_I), modifiers: UInt32(optionKey | cmdKey))
        }
    }

    /// Cómo se pinta en el menú de la barra (informativo: el atajo real es el global).
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags) {
        switch self {
        case .off: return ("i", [.command])
        case .controlOptionCommandI: return ("i", [.control, .option, .command])
        case .controlOptionCommandN: return ("n", [.control, .option, .command])
        case .optionCommandI: return ("i", [.option, .command])
        }
    }
}
