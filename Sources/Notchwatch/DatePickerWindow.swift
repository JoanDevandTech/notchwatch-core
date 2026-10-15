import AppKit
import SwiftUI
import NotchwatchCore

/// Ventanita para elegir una fecha de vencimiento concreta (la isla no puede tomar el foco).
@MainActor
final class DatePickerWindowController {
    private var window: NSWindow?

    func show(for incident: Incident, onPick: @escaping (Date?) -> Void) {
        window?.close()
        let initial = incident.dueOn.flatMap { Formatters.parseDay($0) } ?? Date()
        let view = DueDatePickerView(
            title: incident.name,
            initial: initial,
            onDone: { [weak self] date in
                onPick(date)
                self?.window?.close()
            },
            onCancel: { [weak self] in
                self?.window?.close()
            }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Fecha de vencimiento"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        self.window = window
        AppActivation.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

struct DueDatePickerView: View {
    let title: String
    let onDone: (Date?) -> Void
    let onCancel: () -> Void
    @State private var date: Date

    init(title: String, initial: Date, onDone: @escaping (Date?) -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.onDone = onDone
        self.onCancel = onCancel
        _date = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .lineLimit(2)
            DatePicker("Vence", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "es_ES"))
            HStack {
                Button("Quitar fecha") { onDone(nil) }
                Spacer()
                Button("Cancelar", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Guardar") { onDone(date) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
