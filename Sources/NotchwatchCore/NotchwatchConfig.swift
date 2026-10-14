import Foundation

/// Configuración global de Notchwatch: proyectos vigilados, campo Estado e intervalo de poll.
public struct NotchwatchConfig: Codable, Sendable {
    public var projects: [WatchedProject]
    /// Campo personalizado "Estado".
    public var estadoFieldGid: String
    /// Opción "En curso" del campo Estado.
    public var estadoEnCursoOptionGid: String
    /// Segundos entre polls.
    public var pollInterval: TimeInterval

    public init(
        projects: [WatchedProject],
        estadoFieldGid: String,
        estadoEnCursoOptionGid: String,
        pollInterval: TimeInterval = 20
    ) {
        self.projects = projects
        self.estadoFieldGid = estadoFieldGid
        self.estadoEnCursoOptionGid = estadoEnCursoOptionGid
        self.pollInterval = pollInterval
    }
}

extension PriorityField {
    /// Prioridad global compartida por las 6 apps.
    static let tbcGlobal = PriorityField(
        fieldGid: "1219502866938804",
        options: [
            .baja: "1219502866938805",
            .media: "1219502866938806",
            .urgente: "1219502866938807", // "Incidencia"
            .alta: "1219502866938808", // "Prioridad Alta"
        ]
    )

    /// Prioridad local del proyecto "TBC Incidencias".
    static let tbcIncidenciasLocal = PriorityField(
        fieldGid: "1214164017398881",
        options: [
            .baja: "1214164017398882",
            .media: "1214164017398883",
            .urgente: "1214164017398884",
            .alta: "1214163825159879",
        ]
    )
}

extension NotchwatchConfig {
    /// Configuración por defecto con los 7 proyectos de incidencias de Tubuencamino.
    public static let tubuencamino = NotchwatchConfig(
        projects: [
            WatchedProject(
                key: "ventas",
                name: "Ventas Incidencias",
                projectGid: "1216898612014391",
                sections: ProjectSections(
                    features: "1216898612014392",
                    detectadas: "1219500158564901",
                    verificacion: "1219499888926675",
                    solucion: "1219500158633343",
                    validacion: "1219500227464607",
                    seguimientoInicial: "1219500226457044",
                    seguimientoSemana: "1219500227593143",
                    historico: "1219500158714848"
                ),
                priorityField: .tbcGlobal
            ),
            WatchedProject(
                key: "finanzas",
                name: "Finanzas",
                projectGid: "1217141285197084",
                sections: ProjectSections(
                    features: "1219499860610828",
                    detectadas: "1219500604379856",
                    verificacion: "1219500160154906",
                    solucion: "1219500094667436",
                    validacion: "1219500604510946",
                    seguimientoInicial: "1219500605046803",
                    seguimientoSemana: "1219500161005711",
                    historico: "1219500726951563"
                ),
                priorityField: .tbcGlobal
            ),
            WatchedProject(
                key: "operaciones",
                name: "Operaciones Incidencias",
                projectGid: "1219499889539646",
                sections: ProjectSections(
                    features: "1219499889539666",
                    detectadas: "1219500235314756",
                    verificacion: "1219500160471481",
                    solucion: "1219500095033593",
                    validacion: "1219500235130820",
                    seguimientoInicial: "1219500229209318",
                    seguimientoSemana: "1219500726682552",
                    historico: "1219500236150264"
                ),
                priorityField: .tbcGlobal
            ),
            WatchedProject(
                key: "traslados",
                name: "Traslados Incidencias",
                projectGid: "1219499995234852",
                sections: ProjectSections(
                    features: "1219499995234872",
                    detectadas: "1219500204102700",
                    verificacion: "1219500229228173",
                    solucion: "1219500204089686",
                    validacion: "1219500203757249",
                    seguimientoInicial: "1219500229209321",
                    seguimientoSemana: "1219500161023641",
                    historico: "1219500204779674"
                ),
                priorityField: .tbcGlobal
            ),
            WatchedProject(
                key: "mailing",
                name: "Mailing Incidencias",
                projectGid: "1219500227003727",
                sections: ProjectSections(
                    features: "1219499889365208",
                    detectadas: "1219500095327051",
                    verificacion: "1219500160490434",
                    solucion: "1219499890384555",
                    validacion: "1219500236035263",
                    seguimientoInicial: "1219500235726223",
                    seguimientoSemana: "1219500235467873",
                    historico: "1219500160430963"
                ),
                priorityField: .tbcGlobal
            ),
            WatchedProject(
                key: "mitbc",
                name: "Mi TBC Incidencias",
                projectGid: "1219500159228408",
                sections: ProjectSections(
                    features: "1219500159228428",
                    detectadas: "1219500160461821",
                    verificacion: "1219500604378817",
                    solucion: "1219500604645566",
                    validacion: "1219500204239784",
                    seguimientoInicial: "1219500161007151",
                    seguimientoSemana: "1219515631339719",
                    historico: "1219500160983354"
                ),
                priorityField: .tbcGlobal
            ),
            WatchedProject(
                key: "general",
                name: "TBC Incidencias",
                projectGid: "1214164017398876",
                sections: ProjectSections(
                    features: "1218236710723104",
                    detectadas: "1214164017398877",
                    verificacion: "1214164017398879",
                    solucion: "1214164017398880",
                    validacion: "1214163825159873",
                    seguimientoInicial: "1214163825159874",
                    seguimientoSemana: "1214163825159875",
                    historico: "1214163825159876"
                ),
                priorityField: .tbcIncidenciasLocal
            ),
        ],
        estadoFieldGid: "1214163825159804",
        estadoEnCursoOptionGid: "1214163825159805",
        pollInterval: 20
    )
}
