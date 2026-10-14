import SwiftUI
import NotchwatchCore

/// Fila de una incidencia en la isla desplegada, con sus acciones rápidas.
struct IncidentRow: View {
    @EnvironmentObject private var model: AppModel
    let incident: Incident
    @State private var hovering = false

    private var snoozed: Bool { model.isSnoozed(incident) }

    var body: some View {
        HStack(spacing: 10) {
            Capsule(style: .continuous)
                .fill(incident.priority.tint)
                .frame(width: 4)
                .padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(incident.name)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if snoozed {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                            .help("Pospuesta")
                    }
                }
                HStack(spacing: 6) {
                    ProjectChip(name: incident.projectName)
                    Text(Formatters.relative(incident.createdAt))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                    IncidentMetaLine(incident: incident)
                }
            }
            .opacity(snoozed ? 0.55 : 1)
            Spacer(minLength: 6)
            trailing
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: IslandLayout.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.11 : 0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(incident.priority.tint.opacity(hovering ? 0.45 : 0), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering = $0 }
        .animation(.islandSnappy, value: hovering)
        .contextMenu { contextActions }
    }

    @ViewBuilder
    private var trailing: some View {
        switch model.activity[incident.gid] {
        case .working?:
            ProgressView()
                .controlSize(.small)
                .frame(width: 26, height: 26)
        case .done(let message)?:
            Label(message, systemImage: "checkmark.circle.fill")
                .labelStyle(CompactLabelStyle())
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(Color(red: 0.25, green: 0.86, blue: 0.45))
                .transition(.opacity)
        case .failed(let message)?:
            HStack(spacing: 4) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundColor(Color(red: 1, green: 0.35, blue: 0.35))
                Text(message)
                    .lineLimit(1)
            }
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.85))
            .frame(maxWidth: 170, alignment: .trailing)
            .help(message)
        case nil:
            actions
                .opacity(hovering ? 1 : 0.5)
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            IslandIconButton(symbol: "arrow.up.right", help: "Abrir en Asana") {
                model.open(incident)
            }
            IslandIconButton(symbol: "person.crop.circle.badge.checkmark", help: "Asignármela") {
                model.assignToMe(incident)
            }
            IslandIconButton(symbol: "checkmark.circle", help: "Pasar a Verificación") {
                model.moveToVerification(incident)
            }
            Menu {
                snoozeItems
            } label: {
                MenuIcon(symbol: "moon.zzz")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Posponer")
            Menu {
                dateItems
            } label: {
                MenuIcon(symbol: "calendar")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Cambiar fecha")
            Menu {
                priorityItems
            } label: {
                MenuIcon(symbol: "flag.fill")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Cambiar prioridad")
            IslandIconButton(symbol: "eye.slash", help: "Marcar como vista") {
                model.markSeen(incident)
            }
        }
    }

    @ViewBuilder
    private var snoozeItems: some View {
        Button("15 minutos") { model.snooze(incident, minutes: 15) }
        Button("1 hora") { model.snooze(incident, minutes: 60) }
        Button("4 horas") { model.snooze(incident, minutes: 240) }
        Button("Hasta mañana a las 9:00") { model.snoozeUntilTomorrow(incident) }
    }

    @ViewBuilder
    private var dateItems: some View {
        ForEach(DueDateOption.allCases, id: \.self) { option in
            Button(option.title) { model.setDueDate(incident, option: option) }
        }
        Divider()
        Button("Elegir fecha…") { model.pickDueDate(incident) }
        Button("Quitar fecha") { model.setDueDate(incident, to: nil) }
    }

    @ViewBuilder
    private var priorityItems: some View {
        ForEach(IncidentPriority.menuOrder, id: \.self) { priority in
            Button {
                model.setPriority(incident, to: priority)
            } label: {
                Label(priority.label, systemImage: priority.symbol)
            }
        }
    }

    @ViewBuilder
    private var contextActions: some View {
        Button("Abrir en Asana") { model.open(incident) }
        Button("Asignármela") { model.assignToMe(incident) }
        Button("Pasar a Verificación") { model.moveToVerification(incident) }
        Menu("Posponer") { snoozeItems }
        Menu("Fecha de vencimiento") { dateItems }
        Menu("Prioridad") { priorityItems }
        Divider()
        Button("Marcar como vista") { model.markSeen(incident) }
    }
}
