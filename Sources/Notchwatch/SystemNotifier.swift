import Foundation
import NotchwatchCore
import UserNotifications
import os

/// Permiso de macOS para que Notchwatch muestre notificaciones.
enum NotificationPermission: Equatable {
    /// Fuera de Notchwatch.app (p. ej. con `swift run`) macOS no deja notificar.
    case unavailable
    case notDetermined
    case allowed
    case denied
}

private let notifierLog = Logger(subsystem: "com.joandev.notchwatch", category: "notifications")

/// Notificaciones del Centro de notificaciones de macOS, además de la isla.
/// UserNotifications necesita un bundle con identificador: solo funciona dentro de Notchwatch.app.
final class SystemNotifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    enum Action {
        static let assign = "com.joandev.notchwatch.assign"
        static let snooze = "com.joandev.notchwatch.snooze"
    }

    /// Qué pulsó el usuario en una notificación.
    struct Response: Sendable {
        let incidentGid: String?
        let url: URL?
        let action: String
    }

    static let categoryIdentifier = "com.joandev.notchwatch.incident"

    static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Se llama en el hilo principal al pulsar una notificación o una de sus acciones.
    var onResponse: (@MainActor (Response) -> Void)?

    private let center: UNUserNotificationCenter

    /// `nil` si la app no corre como Notchwatch.app.
    static func make() -> SystemNotifier? {
        guard isSupported else { return nil }
        return SystemNotifier(center: UNUserNotificationCenter.current())
    }

    private init(center: UNUserNotificationCenter) {
        self.center = center
        super.init()
        center.delegate = self
        let assign = UNNotificationAction(identifier: Action.assign, title: "Asignármela", options: [])
        let snooze = UNNotificationAction(identifier: Action.snooze, title: "Posponer 1 h", options: [])
        let category = UNNotificationCategory(
            identifier: SystemNotifier.categoryIdentifier,
            actions: [assign, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// Pide permiso (la primera vez macOS pregunta; después responde al momento).
    func requestAuthorization(_ completion: @escaping @MainActor (NotificationPermission) -> Void) {
        center.requestAuthorization(options: [.alert]) { granted, error in
            if let error {
                notifierLog.error("Permiso de notificaciones: \(error.localizedDescription, privacy: .public)")
            }
            let permission: NotificationPermission = granted ? .allowed : .denied
            Task { @MainActor in completion(permission) }
        }
    }

    func currentPermission(_ completion: @escaping @MainActor (NotificationPermission) -> Void) {
        center.getNotificationSettings { settings in
            let permission: NotificationPermission
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                permission = .allowed
            case .denied:
                permission = .denied
            case .notDetermined:
                permission = .notDetermined
            @unknown default:
                permission = .allowed
            }
            Task { @MainActor in completion(permission) }
        }
    }

    func post(_ payloads: [NotificationPayload]) {
        for payload in payloads {
            let request = UNNotificationRequest(
                identifier: payload.identifier,
                content: makeContent(for: payload),
                trigger: nil
            )
            center.add(request) { error in
                if let error {
                    notifierLog.error("No se pudo notificar: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func makeContent(for payload: NotificationPayload) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.subtitle = payload.subtitle
        content.body = payload.body
        content.threadIdentifier = payload.threadIdentifier
        if !payload.isSummary {
            content.categoryIdentifier = SystemNotifier.categoryIdentifier
        }
        var info: [String: String] = [:]
        if let gid = payload.incidentGid { info["gid"] = gid }
        if let url = payload.url { info["url"] = url.absoluteString }
        content.userInfo = info
        // Sin sonido: ya suena la isla.
        return content
    }

    /// Quita del Centro de notificaciones las de incidencias que ya no están pendientes.
    func withdraw(_ gids: [String]) {
        guard !gids.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: gids)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Con Ajustes abierto la app está en primer plano: que se vean igualmente.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let reply = Response(
            incidentGid: info["gid"] as? String,
            url: (info["url"] as? String).flatMap { URL(string: $0) },
            action: response.actionIdentifier
        )
        Task { @MainActor [weak self] in
            self?.onResponse?(reply)
        }
        completionHandler()
    }
}
