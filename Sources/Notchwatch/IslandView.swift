import SwiftUI
import NotchwatchCore

/// Lienzo completo de la ventana: la isla arriba en el centro y el resto transparente.
struct IslandRootView: View {
    var body: some View {
        VStack(spacing: 0) {
            IslandView()
            Spacer(minLength: 0)
        }
        .frame(width: IslandLayout.canvas.width, height: IslandLayout.canvas.height, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

/// La isla: cambia de forma con muelle entre píldora (reposo), tarjeta (aviso) y panel (desplegada).
struct IslandView: View {
    @EnvironmentObject private var model: AppModel
    var isSnapshot = false
    @Namespace private var namespace
    @State private var bump = false

    var body: some View {
        let mode = model.mode
        let size = IslandLayout.size(
            for: mode,
            notch: model.notch,
            rows: model.listedIncidents.count,
            hasBanner: model.banner != nil
        )
        let shape = NotchShape(
            topRadius: IslandLayout.topRadius(for: mode),
            bottomRadius: IslandLayout.bottomRadius(for: mode, notch: model.notch)
        )

        ZStack(alignment: .top) {
            IslandBackground(accent: model.accentPriority?.tint, lit: mode != .idle)
            content(for: mode)
                .padding(.horizontal, IslandLayout.topRadius(for: mode))
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .overlay(glow(shape: shape))
        .shadow(color: .black.opacity(mode == .idle ? 0 : 0.45), radius: 18, x: 0, y: 8)
        .scaleEffect(bump ? 1.035 : 1, anchor: .top)
        .contentShape(shape)
        .onTapGesture { model.islandTapped() }
        .animation(.islandSpring, value: mode)
        .animation(.islandSpring, value: size)
        .onChange(of: model.arrivalPulse) { _ in
            guard !isSnapshot else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { bump = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 220_000_000)
                withAnimation(.islandSpring) { bump = false }
            }
        }
    }

    @ViewBuilder
    private func content(for mode: IslandMode) -> some View {
        switch mode {
        case .idle:
            IdleContent(namespace: namespace)
        case .peek:
            if let incident = model.peek {
                PeekContent(incident: incident, extra: model.peekExtra, namespace: namespace)
            } else {
                IdleContent(namespace: namespace)
            }
        case .expanded:
            ExpandedContent(namespace: namespace, isSnapshot: isSnapshot)
        }
    }

    @ViewBuilder
    private func glow(shape: NotchShape) -> some View {
        if let priority = model.glowPriority {
            GlowRing(shape: shape, color: priority.tint, pulsing: priority == .urgente, isStatic: isSnapshot)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}

/// Negro profundo; al desplegarse, un brillo muy suave del color de la prioridad sube desde abajo.
private struct IslandBackground: View {
    let accent: Color?
    let lit: Bool

    var body: some View {
        ZStack {
            Color.black
            if let accent, lit {
                RadialGradient(
                    colors: [accent.opacity(0.20), .clear],
                    center: .bottom,
                    startRadius: 0,
                    endRadius: 280
                )
            }
        }
    }
}

// MARK: - Reposo

/// Píldora mínima: icono de estado en la oreja izquierda y contador en la derecha.
/// El centro queda vacío porque ahí está el notch físico.
private struct IdleContent: View {
    @EnvironmentObject private var model: AppModel
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: IslandLayout.earWidth - 8, alignment: .center)
            Spacer(minLength: 0)
            trailing
                .frame(width: IslandLayout.earWidth - 8, alignment: .center)
        }
        .frame(height: model.notch.notchHeight)
    }

    private var leading: some View {
        Image(systemName: model.statusSymbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(model.statusTint)
            .modifier(BounceOnChange(value: model.arrivalPulse))
            .matchedGeometryEffect(id: "glyph", in: namespace)
    }

    @ViewBuilder
    private var trailing: some View {
        if model.visibleCount > 0 {
            Text("\(model.visibleCount)")
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(.white)
                .contentTransition(.numericText())
                .matchedGeometryEffect(id: "count", in: namespace)
        } else {
            Circle()
                .fill(model.hasProblem ? Color.orange : Color.green.opacity(0.85))
                .frame(width: 6, height: 6)
                .matchedGeometryEffect(id: "count", in: namespace)
        }
    }
}

// MARK: - Aviso

/// Tarjeta que asoma bajo el notch cuando entra una incidencia nueva.
private struct PeekContent: View {
    @EnvironmentObject private var model: AppModel
    let incident: Incident
    let extra: Int
    let namespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: model.notch.notchHeight)
            HStack(alignment: .top, spacing: 12) {
                PriorityOrb(priority: incident.priority)
                    .matchedGeometryEffect(id: "glyph", in: namespace)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        PriorityBadge(priority: incident.priority)
                        ProjectChip(name: incident.appLabel)
                        if extra > 0 {
                            Text("+\(extra) más")
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer(minLength: 4)
                        Text(Formatters.relative(incident.createdAt))
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Text(incident.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    IncidentMetaLine(incident: incident)
                }
                VStack(spacing: 6) {
                    IslandIconButton(symbol: "arrow.up.right", help: "Abrir en Asana") {
                        model.open(incident)
                    }
                    IslandIconButton(symbol: "chevron.down", help: "Ver todas") {
                        model.showFromCommand()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Desplegada

private struct ExpandedContent: View {
    @EnvironmentObject private var model: AppModel
    let namespace: Namespace.ID
    let isSnapshot: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: model.notch.notchHeight + IslandLayout.headerHeight, alignment: .bottom)
            if let banner = model.banner {
                BannerView(banner: banner) { model.bannerAction() }
                    .frame(height: IslandLayout.bannerHeight)
                    .padding(.horizontal, 12)
            }
            list
                .layoutPriority(1)
            Spacer(minLength: 0)
            footer
                .frame(height: IslandLayout.footerHeight)
        }
        .padding(.bottom, 6)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.statusSymbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(model.statusTint)
                .matchedGeometryEffect(id: "glyph", in: namespace)
            Text("Incidencias")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("\(model.visibleCount)")
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(.black)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule(style: .continuous).fill(model.accentPriority?.tint ?? Color.white.opacity(0.85)))
                .contentTransition(.numericText())
                .matchedGeometryEffect(id: "count", in: namespace)
            FilterSwitch()
                .padding(.leading, 2)
            if model.isPaused {
                Label("En pausa", systemImage: "bell.slash.fill")
                    .labelStyle(CompactLabelStyle())
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
            IslandIconButton(symbol: "arrow.clockwise", help: "Actualizar ahora") {
                model.refreshNow()
            }
            IslandIconButton(
                symbol: model.isPaused ? "bell.fill" : "bell.slash",
                help: model.isPaused ? "Reanudar avisos" : "Pausar avisos 1 h"
            ) {
                model.togglePause()
            }
            IslandIconButton(symbol: "gearshape.fill", help: "Ajustes") {
                model.openSettings()
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var list: some View {
        let items = model.listedIncidents
        if items.isEmpty {
            if model.settings.showOnlyMine && !model.pending.isEmpty {
                EmptyMineView(total: model.pending.count, loading: !model.isUserKnown) { model.setShowOnlyMine(false) }
                    .frame(height: 96)
            } else {
                EmptyStateView(hasToken: model.hasToken || model.isDemo) { model.openSettings() }
                    .frame(height: 96)
            }
        } else if isSnapshot {
            VStack(spacing: IslandLayout.rowSpacing) {
                ForEach(items.prefix(IslandLayout.maxVisibleRows)) { incident in
                    // En las capturas, la primera fila se pinta "con el ratón encima" para enseñar las acciones.
                    IncidentRow(incident: incident, previewHover: incident.gid == items.first?.gid)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: IslandLayout.rowSpacing) {
                    ForEach(items) { incident in
                        IncidentRow(incident: incident)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity.combined(with: .scale(scale: 0.96))
                            ))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .animation(.islandSnappy, value: items.map(\.gid))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let name = model.userName {
                Label(name, systemImage: "person.crop.circle")
                    .labelStyle(CompactLabelStyle())
            }
            Spacer()
            if let last = model.lastPoll {
                Text("Actualizado \(Formatters.relative(last))")
            }
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundColor(.white.opacity(0.4))
        .padding(.horizontal, 16)
    }
}

/// Selector «Todas / Mías» de la cabecera: la cápsula clara se desliza a la opción elegida.
private struct FilterSwitch: View {
    @EnvironmentObject private var model: AppModel
    @Namespace private var selection

    var body: some View {
        let onlyMine = model.settings.showOnlyMine
        HStack(spacing: 2) {
            segment("Todas", count: nil, selected: !onlyMine, help: "Ver todas las incidencias") {
                model.setShowOnlyMine(false)
            }
            segment("Mías", count: model.mineCount, selected: onlyMine, help: "Ver solo las asignadas a ti") {
                model.setShowOnlyMine(true)
            }
        }
        .padding(2)
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.08)))
    }

    private func segment(
        _ title: String,
        count: Int?,
        selected: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let count, count > 0 {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(selected ? 0.75 : 0.45))
                }
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(selected ? 1 : 0.55))
            .padding(.horizontal, 9)
            .padding(.vertical, 3.5)
            .background {
                if selected {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Filtro «Mías» sin resultados: ninguna pendiente está asignada a ti.
private struct EmptyMineView: View {
    let total: Int
    /// Aún no se sabe quién es el usuario del token (arrancando o sin conexión).
    let loading: Bool
    let showAll: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Color.mineTint)
            Text(loading ? "Cargando tu usuario de Asana…" : "No tienes incidencias asignadas")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            Button(total == 1 ? "Ver la pendiente" : "Ver las \(total) pendientes", action: showAll)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Color.mineTint)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BannerView: View {
    let banner: IslandBanner
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(tint)
            Text(banner.text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 6)
            if let title = banner.actionTitle {
                Button(title, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.14)))
        .padding(.vertical, 3)
    }

    private var symbol: String {
        switch banner.kind {
        case .warning: return "exclamationmark.triangle.fill"
        case .update: return "arrow.down.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var tint: Color {
        switch banner.kind {
        case .warning: return .orange
        case .update: return Color(red: 0.4, green: 0.7, blue: 1)
        case .info: return .white
        }
    }
}

private struct EmptyStateView: View {
    let hasToken: Bool
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: hasToken ? "checkmark.seal.fill" : "key.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(hasToken ? Color(red: 0.25, green: 0.86, blue: 0.45) : .orange)
            Text(hasToken ? "Todo en orden" : "Configura tu token de Asana")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            if hasToken {
                Text("No hay incidencias pendientes")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                Button("Abrir ajustes", action: openSettings)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
