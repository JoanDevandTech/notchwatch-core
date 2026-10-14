import AppKit
import SwiftUI
import NotchwatchCore

/// `--snapshot <dir>`: pinta cada estado de la isla en PNG (sin pantalla ni red). Lo usa la CI
/// para generar capturas que se pueden revisar sin abrir la app.
@MainActor
enum SnapshotRenderer {
    private struct Scenario {
        let name: String
        let mode: IslandMode
        let pending: [Incident]
        let peek: Incident?
    }

    static func renderAll(to directory: String) -> Int32 {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("No se pudo crear \(directory): \(error)\n".utf8))
            return 1
        }
        let now = Date()
        let samples = DemoData.initialIncidents(now: now)
        let scenarios = [
            Scenario(name: "1-reposo-sin-incidencias", mode: .idle, pending: [], peek: nil),
            Scenario(name: "2-reposo-con-pendientes", mode: .idle, pending: samples, peek: nil),
            Scenario(name: "3-aviso-urgente", mode: .peek, pending: samples, peek: DemoData.sample(.urgente, now: now)),
            Scenario(name: "4-aviso-alta", mode: .peek, pending: samples, peek: DemoData.sample(.alta, now: now)),
            Scenario(name: "5-aviso-media", mode: .peek, pending: samples, peek: DemoData.sample(.media, now: now)),
            Scenario(name: "6-aviso-baja", mode: .peek, pending: samples, peek: DemoData.sample(.baja, now: now)),
            Scenario(name: "7-desplegada", mode: .expanded, pending: samples, peek: nil),
            Scenario(name: "8-desplegada-vacia", mode: .expanded, pending: [], peek: nil),
        ]
        var failures: Int32 = 0
        for scenario in scenarios {
            let model = AppModel(demo: true, snapshot: true)
            model.applySnapshot(mode: scenario.mode, pending: scenario.pending, peek: scenario.peek)
            let renderer = ImageRenderer(content: SnapshotCanvas().environmentObject(model))
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:])
            else {
                FileHandle.standardError.write(Data("Fallo al renderizar \(scenario.name)\n".utf8))
                failures += 1
                continue
            }
            do {
                try png.write(to: url.appendingPathComponent("\(scenario.name).png"))
                FileHandle.standardOutput.write(Data("Captura \(scenario.name).png\n".utf8))
            } catch {
                failures += 1
            }
        }
        return failures == 0 ? 0 : 1
    }
}

/// Fondo de escritorio + barra de menús + isla, para que las capturas se entiendan solas.
struct SnapshotCanvas: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let size = IslandLayout.size(
            for: model.mode,
            notch: model.notch,
            rows: model.listedIncidents.count,
            hasBanner: model.banner != nil
        )
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.2, blue: 0.4), Color(red: 0.45, green: 0.24, blue: 0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Rectangle()
                .fill(Color.black.opacity(0.28))
                .frame(height: model.notch.notchHeight)
            IslandView(isSnapshot: true)
        }
        .frame(width: max(size.width + 180, 680), height: size.height + 90, alignment: .top)
        .environment(\.colorScheme, .dark)
        .environment(\.isSnapshotRender, true)
    }
}
