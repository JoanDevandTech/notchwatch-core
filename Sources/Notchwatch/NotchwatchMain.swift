import AppKit

/// Punto de entrada: app de barra de menús (sin Dock) que controla su propio NSPanel.
@main
enum NotchwatchMain {
    @MainActor
    static func main() {
        let arguments = LaunchArguments(CommandLine.arguments)
        let app = NSApplication.shared
        _ = app.setActivationPolicy(.accessory)
        let delegate = AppDelegate(arguments: arguments)
        // NSApplication guarda el delegate como referencia débil: lo retenemos aquí.
        AppDelegate.shared = delegate
        app.delegate = delegate
        app.run()
    }
}

/// Flags de línea de comandos.
/// - `--demo`: sin token, genera incidencias falsas para ver la isla en acción.
/// - `--self-test`: arranca la UI sin red, imprime "SELF-TEST OK" y sale (lo usa la CI).
/// - `--snapshot <dir>`: renderiza capturas PNG de cada estado de la isla y sale.
struct LaunchArguments {
    var demo = false
    var selfTest = false
    var snapshotDirectory: String?

    init(_ arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--demo":
                demo = true
            case "--self-test":
                selfTest = true
            case "--snapshot":
                snapshotDirectory = iterator.next() ?? "snapshots"
            default:
                break
            }
        }
    }
}
