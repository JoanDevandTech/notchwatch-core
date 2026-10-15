import Foundation

/// Preajustes de fuentes conocidas.
public enum AsanaPresets {
    public static let tubuencaminoSourceID = "asana-tubuencamino"

    /// Campo de prioridad global compartido por seis de los proyectos de Tubuencamino.
    static let tbcGlobalPriority = PriorityField(
        fieldGid: "1219502866938804",
        options: [
            .baja: "1219502866938805",
            .media: "1219502866938806",
            .urgente: "1219502866938807",
            .alta: "1219502866938808",
        ]
    )

    /// Prioridad local del proyecto «TBC Incidencias».
    static let tbcLocalPriority = PriorityField(
        fieldGid: "1214164017398881",
        options: [
            .baja: "1214164017398882",
            .media: "1214164017398883",
            .urgente: "1214164017398884",
            .alta: "1214163825159879",
        ]
    )

    static let tbcStatus = StatusField(
        fieldGid: "1214163825159804",
        inProgressOptionGid: "1214163825159805",
        solvedOptionGid: "1214163825159829"
    )
    static let tbcReporterFieldGid = "1216067243827070"
    static let tbcModuleFieldGid = "1216067230748421"

    /// Los siete proyectos de incidencias de Tubuencamino. El GID del workspace no hace falta para
    /// leer ni actuar sobre los proyectos; la app lo rellena al aplicar el preajuste con un token.
    public static let tubuencamino = AsanaSourceConfig(
        id: tubuencaminoSourceID,
        displayName: "Tubuencamino",
        workspaceGid: "1214149525879142",
        workspaceName: "Tubuencamino",
        projects: [
            tubuencaminoProject(
                key: "ventas", name: "Ventas", projectName: "Ventas Incidencias",
                projectGid: "1216898612014391", detected: "1219500158564901", resolved: "1219499888926675",
                style: CollectionStyle(symbol: "chart.bar.fill", colorHex: "#DFB47D")
            ),
            tubuencaminoProject(
                key: "finanzas", name: "Finanzas", projectName: "Finanzas",
                projectGid: "1217141285197084", detected: "1219500604379856", resolved: "1219500160154906",
                style: CollectionStyle(symbol: "creditcard.fill", colorHex: "#E78580")
            ),
            tubuencaminoProject(
                key: "operaciones", name: "Operaciones", projectName: "Operaciones Incidencias",
                projectGid: "1219499889539646", detected: "1219500235314756", resolved: "1219500160471481",
                style: CollectionStyle(symbol: "shippingbox.fill", colorHex: "#85BAA8")
            ),
            tubuencaminoProject(
                key: "traslados", name: "Traslados", projectName: "Traslados Incidencias",
                projectGid: "1219499995234852", detected: "1219500204102700", resolved: "1219500229228173",
                style: CollectionStyle(symbol: "car.fill", colorHex: "#D8C790")
            ),
            tubuencaminoProject(
                key: "mailing", name: "Mailing", projectName: "Mailing Incidencias",
                projectGid: "1219500227003727", detected: "1219500095327051", resolved: "1219500160490434",
                style: CollectionStyle(symbol: "envelope.fill", colorHex: "#B3CBEC")
            ),
            tubuencaminoProject(
                key: "mitbc", name: "Mi TBC", projectName: "Mi TBC Incidencias",
                projectGid: "1219500159228408", detected: "1219500160461821", resolved: "1219500604378817",
                style: CollectionStyle(symbol: "person.crop.circle.fill", colorHex: "#C9A7E0")
            ),
            tubuencaminoProject(
                key: "general", name: "TBC", projectName: "TBC Incidencias",
                projectGid: "1214164017398876", detected: "1214164017398877", resolved: "1214164017398879",
                priority: tbcLocalPriority,
                style: CollectionStyle(symbol: "flame.fill", colorHex: "#E78580")
            ),
        ]
    )

    private static func tubuencaminoProject(
        key: String,
        name: String,
        projectName: String,
        projectGid: String,
        detected: String,
        resolved: String,
        priority: PriorityField = tbcGlobalPriority,
        style: CollectionStyle
    ) -> AsanaProjectConfig {
        AsanaProjectConfig(
            collection: WatchedCollection(
                id: WatchedCollection.makeID(sourceID: tubuencaminoSourceID, key: key),
                name: name,
                style: style
            ),
            projectGid: projectGid,
            projectName: projectName,
            detectedSectionGid: detected,
            resolvedSectionGid: resolved,
            priorityField: priority,
            statusField: tbcStatus,
            reporterFieldGid: tbcReporterFieldGid,
            moduleFieldGid: tbcModuleFieldGid
        )
    }
}
