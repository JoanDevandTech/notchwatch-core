import Foundation
import ServiceManagement

/// "Iniciar al arrancar el Mac" con SMAppService (macOS 13+).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Devuelve un mensaje de error si no se pudo cambiar, o `nil` si fue bien.
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "No se pudo cambiar: \(error.localizedDescription). Mueve Notchwatch a Aplicaciones y vuelve a intentarlo."
        }
    }
}
