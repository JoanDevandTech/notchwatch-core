# NotchwatchCore

Núcleo de **Notchwatch**, la isla de incidencias para el notch del Mac. Es un paquete Swift sin interfaz, solo Foundation, que compila y se testea en macOS y en Linux. La app de escritorio vive en [`JoanDevandTech/notchwatch`](https://github.com/JoanDevandTech/notchwatch) y lo consume como dependencia.

## Qué contiene

| Módulo | Responsabilidad |
|---|---|
| `Models` | `Incident`, `IncidentPriority`, `SourceError`, resultados de diff y poll. |
| `Sources/IncidentSource` | Protocolo de fuente de incidencias (`IncidentSource`), colecciones vigiladas, estilos, capacidades y acciones (asignármela, en curso, resolver, vencimiento y prioridad). Cualquier app nueva (Jira, GitHub…) se integra implementándolo. |
| `Sources/Asana` | `AsanaClient` (REST, paginación, 401/429), `AsanaSource`, descubrimiento de workspaces/proyectos/secciones/campos, `AsanaConfigurator` (propone la configuración de un proyecto por los nombres de sus secciones y campos) y el preajuste `AsanaPresets.tubuencamino`. «En curso» pone el campo de estado del proyecto en su opción «en curso» y asigna la tarea al usuario solo si no tiene responsable. Además de la sección «detectadas», cada proyecto trae las **subtareas sin completar asignadas al usuario** cuya tarea madre está en el proyecto, en cualquier sección (una sola petición `GET /tasks?assignee=me&workspace=…` compartida entre proyectos). En una subtarea «Resolver» la marca completada, «En curso» solo la asigna si no tiene responsable y la prioridad no aplica. |
| `IncidentMonitor` | Actor que lee todas las colecciones de todas las fuentes en paralelo, decide qué es nuevo, toma la línea base por colección y persiste vistas, pospuestas y responsables (`SeenStore`). Con el alcance «Solo las mías» (`updateScope(.mine, for: usuario)`) solo avisa de las asignadas al usuario y una incidencia que le reasignan se avisa como nueva; `pending` sigue trayendo todas. |
| `Settings` | Modelos de ajustes: apariencia (tema, colores por prioridad, tipografía), sonido (motivo por prioridad, volumen, No molestar), comportamiento (lectura, movimiento, atajo y alcance: solo las mías, por defecto, o todas) y `NotchwatchProfile`, el perfil completo exportable sin credenciales. |
| `NotificationPlanner` | Texto de las notificaciones del sistema (una por incidencia o un resumen), con las cadenas inyectadas por la app. |
| `ConsoleSummaryParser` | Lee «Errores consola: X/Y» de las notas de un ticket. |

Las credenciales nunca pasan por aquí: la app las guarda en el Llavero y las entrega a la fuente al crearla.

## Uso

```swift
import NotchwatchCore

let source = AsanaSource(config: AsanaPresets.tubuencamino, token: token)
let monitor = IncidentMonitor(sources: [source], storeURL: stateURL)
let outcome = await monitor.poll()
outcome.newIncidents   // lo que hay que avisar
outcome.pending        // todo lo abierto y no visto
outcome.errors         // por colección
```

Alta de una cuenta nueva de Asana:

```swift
let client = AsanaClient(token: token)
let workspace = try await client.workspaces().first!
let projects = try await client.projects(inWorkspace: workspace.gid)
let layout = try await client.layout(of: projects[0])
let proposal = AsanaConfigurator.suggest(for: layout, sourceID: "asana-miempresa")
```

## Desarrollo

```bash
swift build
swift test            # macOS o Linux (Swift 6.0+)
```

La CI pasa los tests en Linux y macOS y falla si el compilador emite algún aviso.

## Diseño

- Todo lo público es `Sendable`; `IncidentMonitor` es un actor.
- Los ajustes se decodifican de forma tolerante: cualquier campo ausente toma su valor por defecto, así los perfiles antiguos siguen cargando.
- Los tests usan fixtures JSON reales de la API de Asana y un transporte falso; no hay red.
