import Foundation
import XCTest
@testable import NotchwatchCore

/// Calendario gregoriano con zona fija para no depender de la configuración del runner.
private func madridCalendar() throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Madrid"))
    return calendar
}

/// 14/10/2026 a la hora indicada, en el calendario dado.
private func october14(_ hour: Int, _ minute: Int = 0, in calendar: Calendar) throws -> Date {
    try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: hour, minute: minute)))
}

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: Data(json.utf8))
}

final class QuietHoursTests: XCTestCase {
    func testDefaultsAreNightRangeDisabled() {
        let quiet = QuietHours()
        XCTAssertFalse(quiet.enabled)
        XCTAssertEqual(quiet.startMinute, 22 * 60)
        XCTAssertEqual(quiet.endMinute, 8 * 60)
    }

    func testDisabledNeverContains() throws {
        let calendar = try madridCalendar()
        let quiet = QuietHours(enabled: false, startMinute: 0, endMinute: 1439)
        XCTAssertFalse(quiet.contains(try october14(12, 0, in: calendar), calendar: calendar))
    }

    func testSameDayRange() throws {
        let calendar = try madridCalendar()
        let quiet = QuietHours(enabled: true, startMinute: 13 * 60, endMinute: 15 * 60)
        XCTAssertFalse(quiet.contains(try october14(12, 59, in: calendar), calendar: calendar))
        XCTAssertTrue(quiet.contains(try october14(13, 0, in: calendar), calendar: calendar))
        XCTAssertTrue(quiet.contains(try october14(14, 30, in: calendar), calendar: calendar))
        XCTAssertFalse(quiet.contains(try october14(15, 0, in: calendar), calendar: calendar))
    }

    func testRangeCrossingMidnight() throws {
        let calendar = try madridCalendar()
        let quiet = QuietHours(enabled: true, startMinute: 22 * 60, endMinute: 8 * 60)
        XCTAssertFalse(quiet.contains(try october14(21, 59, in: calendar), calendar: calendar))
        XCTAssertTrue(quiet.contains(try october14(22, 0, in: calendar), calendar: calendar))
        XCTAssertTrue(quiet.contains(try october14(23, 30, in: calendar), calendar: calendar))
        XCTAssertTrue(quiet.contains(try october14(0, 0, in: calendar), calendar: calendar))
        XCTAssertTrue(quiet.contains(try october14(3, 15, in: calendar), calendar: calendar))
        XCTAssertTrue(quiet.contains(try october14(7, 59, in: calendar), calendar: calendar))
        XCTAssertFalse(quiet.contains(try october14(8, 0, in: calendar), calendar: calendar))
        XCTAssertFalse(quiet.contains(try october14(12, 0, in: calendar), calendar: calendar))
    }

    func testSameInstantDependsOnCalendarTimeZone() throws {
        // 23:30 en Madrid (CEST, UTC+2) son las 21:30 UTC: fuera de 22:00–08:00 en UTC.
        let madrid = try madridCalendar()
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let quiet = QuietHours(enabled: true, startMinute: 22 * 60, endMinute: 8 * 60)
        let instant = try october14(23, 30, in: madrid)

        XCTAssertTrue(quiet.contains(instant, calendar: madrid))
        XCTAssertFalse(quiet.contains(instant, calendar: utc))
    }

    func testEmptyRangeWhenStartEqualsEnd() throws {
        let calendar = try madridCalendar()
        let quiet = QuietHours(enabled: true, startMinute: 600, endMinute: 600)
        XCTAssertFalse(quiet.contains(try october14(10, 0, in: calendar), calendar: calendar))
        XCTAssertFalse(quiet.contains(try october14(3, 0, in: calendar), calendar: calendar))
    }

    func testOutOfRangeMinutesAreNormalized() throws {
        let calendar = try madridCalendar()
        // -60 = 23:00 y 1500 = 01:00 del día siguiente.
        let quiet = QuietHours(enabled: true, startMinute: -60, endMinute: 1500)
        XCTAssertTrue(quiet.contains(try october14(23, 30, in: calendar), calendar: calendar))
        XCTAssertTrue(quiet.contains(try october14(0, 30, in: calendar), calendar: calendar))
        XCTAssertFalse(quiet.contains(try october14(1, 0, in: calendar), calendar: calendar))
        XCTAssertFalse(quiet.contains(try october14(22, 59, in: calendar), calendar: calendar))
    }

    func testCodableRoundTrip() throws {
        let quiet = QuietHours(enabled: true, startMinute: 1320, endMinute: 480)
        let data = try JSONEncoder().encode(quiet)
        XCTAssertEqual(try JSONDecoder().decode(QuietHours.self, from: data), quiet)
    }
}

final class DoNotDisturbTests: XCTestCase {
    func testManualIndefiniteIsAlwaysActive() throws {
        let calendar = try madridCalendar()
        let dnd = DoNotDisturb(manual: .indefinite)
        XCTAssertTrue(dnd.isActive(at: try october14(12, in: calendar), calendar: calendar))
        XCTAssertNil(dnd.manualEnd)
    }

    func testManualUntilExpires() throws {
        let calendar = try madridCalendar()
        let end = try october14(13, in: calendar)
        let dnd = DoNotDisturb(manual: .until(end))
        XCTAssertTrue(dnd.isActive(at: try october14(12, 59, in: calendar), calendar: calendar))
        XCTAssertFalse(dnd.isActive(at: end, calendar: calendar))
        XCTAssertFalse(dnd.isActive(at: try october14(14, in: calendar), calendar: calendar))
        XCTAssertEqual(dnd.manualEnd, end)
    }

    func testScheduleAppliesWhenManualIsOffOrExpired() throws {
        let calendar = try madridCalendar()
        let night = QuietHours(enabled: true, startMinute: 22 * 60, endMinute: 8 * 60)
        let off = DoNotDisturb(manual: .off, schedule: night)
        XCTAssertTrue(off.isActive(at: try october14(23, in: calendar), calendar: calendar))
        XCTAssertFalse(off.isActive(at: try october14(12, in: calendar), calendar: calendar))

        let expired = DoNotDisturb(manual: .until(try october14(1, in: calendar)), schedule: night)
        XCTAssertTrue(expired.isActive(at: try october14(23, in: calendar), calendar: calendar))
        XCTAssertFalse(expired.isActive(at: try october14(12, in: calendar), calendar: calendar))
    }

    func testCodableRoundTripOfManualCases() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for manual in [DoNotDisturb.Manual.off, .indefinite, .until(isoDate("2026-10-14T13:00:00Z"))] {
            let dnd = DoNotDisturb(manual: manual, urgentBreaksThrough: false)
            let data = try encoder.encode(dnd)
            XCTAssertEqual(try decoder.decode(DoNotDisturb.self, from: data), dnd)
        }
    }
}

final class SoundSettingsTests: XCTestCase {
    private let night = QuietHours(enabled: true, startMinute: 22 * 60, endMinute: 8 * 60)

    func testDefaults() {
        let settings = SoundSettings.default
        XCTAssertFalse(settings.muted)
        XCTAssertEqual(settings.volume, 0.6)
        XCTAssertEqual(settings.motifs, SoundSettings.defaultMotifs)
        XCTAssertEqual(settings.doNotDisturb, DoNotDisturb())
        XCTAssertEqual(settings.loudRepeatInterval, 30)
        XCTAssertTrue(settings.repeatsLoud)
        XCTAssertEqual(settings.motif(for: .urgente), .alarm)
        XCTAssertEqual(settings.motif(for: .ninguna), .tick)
    }

    func testNormalDecisionSoundsAndRepeatsOnlyLoud() throws {
        let calendar = try madridCalendar()
        let noon = try october14(12, in: calendar)
        let settings = SoundSettings()
        XCTAssertEqual(settings.decision(for: .urgente, at: noon, calendar: calendar), AlertDecision(motif: .alarm, showsAlert: true, repeats: true))
        XCTAssertEqual(settings.decision(for: .alta, at: noon, calendar: calendar), AlertDecision(motif: .triad, showsAlert: true, repeats: true))
        XCTAssertEqual(settings.decision(for: .media, at: noon, calendar: calendar), AlertDecision(motif: .chime, showsAlert: true, repeats: false))
        XCTAssertEqual(settings.decision(for: .baja, at: noon, calendar: calendar), AlertDecision(motif: .drop, showsAlert: true, repeats: false))
        XCTAssertEqual(settings.decision(for: .ninguna, at: noon, calendar: calendar), AlertDecision(motif: .tick, showsAlert: true, repeats: false))
    }

    func testMutedShowsAlertWithoutSoundNorRepeat() throws {
        let calendar = try madridCalendar()
        let settings = SoundSettings(muted: true)
        for priority in IncidentPriority.allCases {
            let decision = settings.decision(for: priority, at: try october14(12, in: calendar), calendar: calendar)
            XCTAssertEqual(decision, AlertDecision(motif: nil, showsAlert: true, repeats: false), "\(priority)")
        }
    }

    func testRepeatsLoudOffNeverRepeats() throws {
        let calendar = try madridCalendar()
        let settings = SoundSettings(repeatsLoud: false)
        let decision = settings.decision(for: .urgente, at: try october14(12, in: calendar), calendar: calendar)
        XCTAssertEqual(decision, AlertDecision(motif: .alarm, showsAlert: true, repeats: false))
    }

    func testManualIndefiniteDoNotDisturbOnlyUrgentBreaksThrough() throws {
        let calendar = try madridCalendar()
        let noon = try october14(12, in: calendar)
        let settings = SoundSettings(doNotDisturb: DoNotDisturb(manual: .indefinite))
        XCTAssertEqual(settings.decision(for: .urgente, at: noon, calendar: calendar), AlertDecision(motif: .alarm, showsAlert: true, repeats: true))
        XCTAssertEqual(settings.decision(for: .alta, at: noon, calendar: calendar), .silent)
        XCTAssertEqual(settings.decision(for: .media, at: noon, calendar: calendar), .silent)

        let strict = SoundSettings(doNotDisturb: DoNotDisturb(manual: .indefinite, urgentBreaksThrough: false))
        XCTAssertEqual(strict.decision(for: .urgente, at: noon, calendar: calendar), .silent)

        // Silenciado y con «No molestar», la urgente se muestra pero no suena.
        let mutedToo = SoundSettings(muted: true, doNotDisturb: DoNotDisturb(manual: .indefinite))
        XCTAssertEqual(mutedToo.decision(for: .urgente, at: noon, calendar: calendar), AlertDecision(motif: nil, showsAlert: true, repeats: false))
    }

    func testDoNotDisturbUntilPastIsInactive() throws {
        let calendar = try madridCalendar()
        let settings = SoundSettings(doNotDisturb: DoNotDisturb(manual: .until(try october14(11, in: calendar))))
        let decision = settings.decision(for: .media, at: try october14(12, in: calendar), calendar: calendar)
        XCTAssertEqual(decision, AlertDecision(motif: .chime, showsAlert: true, repeats: false))
    }

    func testScheduleCrossingMidnightSilencesExceptUrgent() throws {
        let calendar = try madridCalendar()
        let settings = SoundSettings(doNotDisturb: DoNotDisturb(schedule: night))
        XCTAssertEqual(settings.decision(for: .alta, at: try october14(23, 30, in: calendar), calendar: calendar), .silent)
        XCTAssertEqual(settings.decision(for: .media, at: try october14(3, in: calendar), calendar: calendar), .silent)
        XCTAssertEqual(settings.decision(for: .baja, at: try october14(7, 59, in: calendar), calendar: calendar), .silent)
        XCTAssertEqual(settings.decision(for: .urgente, at: try october14(2, in: calendar), calendar: calendar).motif, .alarm)
        // A las 08:00 termina el silencio.
        XCTAssertEqual(settings.decision(for: .alta, at: try october14(8, in: calendar), calendar: calendar).motif, .triad)
        XCTAssertEqual(settings.decision(for: .media, at: try october14(21, 59, in: calendar), calendar: calendar).motif, .chime)
    }

    // MARK: - Decodificación tolerante

    func testEmptyJSONDecodesToDefaults() throws {
        XCTAssertEqual(try decode(SoundSettings.self, "{}"), .default)
    }

    func testPartialMotifsMergeWithDefaults() throws {
        let settings = try decode(SoundSettings.self, #"{"motifs":{"urgente":"glass"},"volume":1.7}"#)
        XCTAssertEqual(settings.motif(for: .urgente), .glass)
        XCTAssertEqual(settings.motif(for: .alta), .triad)
        XCTAssertEqual(settings.motifs.count, 5)
        // El volumen se recorta a 0…1.
        XCTAssertEqual(settings.volume, 1)
    }

    func testCodableRoundTrip() throws {
        let settings = SoundSettings(
            muted: true,
            volume: 0.3,
            motifs: [.urgente: .glass, .baja: .tick],
            doNotDisturb: DoNotDisturb(manual: .indefinite, schedule: night, urgentBreaksThrough: false),
            loudRepeatInterval: 45,
            repeatsLoud: false
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(SoundSettings.self, from: data)
        // Los motivos no indicados vuelven con el valor por defecto.
        XCTAssertEqual(decoded.motifs, SoundSettings.defaultMotifs.merging([.urgente: .glass, .baja: .tick]) { _, custom in custom })
        XCTAssertEqual(decoded.muted, true)
        XCTAssertEqual(decoded.volume, 0.3)
        XCTAssertEqual(decoded.doNotDisturb, settings.doNotDisturb)
        XCTAssertEqual(decoded.loudRepeatInterval, 45)
        XCTAssertFalse(decoded.repeatsLoud)
    }
}

final class AppearanceSettingsTests: XCTestCase {
    func testEmptyJSONDecodesToDefaults() throws {
        XCTAssertEqual(try decode(AppearanceSettings.self, "{}"), .default)
    }

    func testPartialPriorityColorsMergeWithDefaults() throws {
        let appearance = try decode(AppearanceSettings.self, ##"{"theme":"dark","priorityColors":{"urgente":"#FF0000"}}"##)
        XCTAssertEqual(appearance.theme, .dark)
        XCTAssertEqual(appearance.color(for: .urgente), "#FF0000")
        XCTAssertEqual(appearance.color(for: .alta), AppearanceSettings.defaultPriorityColors[.alta])
        XCTAssertEqual(appearance.priorityColors.count, 5)
        XCTAssertEqual(appearance.fontDesign, .system)
        XCTAssertEqual(appearance.textScale, .regular)
    }

    func testColorFallsBackForMissingPriority() {
        var appearance = AppearanceSettings()
        appearance.priorityColors = [:]
        XCTAssertEqual(appearance.color(for: .baja), "#85BAA8")
    }

    func testTextScaleFactors() {
        XCTAssertEqual(TextScale.small.factor, 0.92)
        XCTAssertEqual(TextScale.regular.factor, 1)
        XCTAssertEqual(TextScale.large.factor, 1.1)
    }

    func testCodableRoundTrip() throws {
        let appearance = AppearanceSettings(theme: .light, priorityColors: [.media: "#123456"], fontDesign: .rounded, textScale: .large)
        let data = try JSONEncoder().encode(appearance)
        let decoded = try JSONDecoder().decode(AppearanceSettings.self, from: data)
        XCTAssertEqual(decoded.theme, .light)
        XCTAssertEqual(decoded.color(for: .media), "#123456")
        XCTAssertEqual(decoded.fontDesign, .rounded)
        XCTAssertEqual(decoded.textScale, .large)
    }
}

final class BehaviorSettingsTests: XCTestCase {
    func testEmptyJSONDecodesToDefaults() throws {
        XCTAssertEqual(try decode(BehaviorSettings.self, "{}"), .default)
        XCTAssertEqual(BehaviorSettings.default.pollInterval, 20)
        XCTAssertEqual(BehaviorSettings.default.hotKey, .controlOptionCommandI)
        XCTAssertNil(BehaviorSettings.default.preferredScreenID)
    }

    func testPollIntervalHasAFloorOfTenSeconds() throws {
        XCTAssertEqual(try decode(BehaviorSettings.self, #"{"pollInterval":3}"#).pollInterval, 10)
        XCTAssertEqual(try decode(BehaviorSettings.self, #"{"pollInterval":45}"#).pollInterval, 45)
    }

    func testMotionIntervals() {
        XCTAssertEqual(MotionIntensity.off.ambientInterval, 0)
        XCTAssertEqual(MotionIntensity.subtle.ambientInterval, 16)
        XCTAssertEqual(MotionIntensity.normal.ambientInterval, 8)
        XCTAssertEqual(MotionIntensity.lively.ambientInterval, 4)
    }

    func testCodableRoundTrip() throws {
        let behavior = BehaviorSettings(
            pollInterval: 60,
            motion: .lively,
            expandOnHover: false,
            alertDuration: 12,
            systemNotifications: false,
            hotKey: .off,
            showOnlyMine: true,
            preferredScreenID: "screen-2"
        )
        let data = try JSONEncoder().encode(behavior)
        XCTAssertEqual(try JSONDecoder().decode(BehaviorSettings.self, from: data), behavior)
    }
}

final class NotchwatchProfileTests: XCTestCase {
    func testEmptyJSONDecodesToEmptyProfile() throws {
        let profile = try decode(NotchwatchProfile.self, "{}")
        XCTAssertEqual(profile, .empty)
        XCTAssertEqual(profile.version, NotchwatchProfile.currentVersion)
        XCTAssertTrue(profile.sources.isEmpty)
        XCTAssertTrue(profile.collections.isEmpty)
    }

    func testCollectionsAggregateSources() {
        let profile = NotchwatchProfile(sources: [.asana(AsanaPresets.tubuencamino)])
        XCTAssertEqual(profile.collections.count, 7)
        XCTAssertEqual(profile.collection(id: tbcCollectionID("finanzas"))?.name, "Finanzas")
        XCTAssertNil(profile.collection(id: "nada"))
        XCTAssertEqual(profile.sources.first?.id, "asana-tubuencamino")
        XCTAssertEqual(profile.sources.first?.kind, .asana)
        XCTAssertEqual(profile.sources.first?.displayName, "Tubuencamino")
    }

    func testProfileCodecRoundTripWithAsanaSource() throws {
        var preset = AsanaPresets.tubuencamino
        preset.projects[1].collection.enabled = false
        let profile = NotchwatchProfile(
            sources: [.asana(preset)],
            // Los colores se guardan completos: al decodificar se fusionan con los por defecto.
            appearance: AppearanceSettings(
                theme: .dark,
                priorityColors: AppearanceSettings.defaultPriorityColors.merging([.urgente: "#FF0000"]) { _, custom in custom }
            ),
            sound: SoundSettings(muted: true, doNotDisturb: DoNotDisturb(manual: .until(isoDate("2026-10-14T13:00:00Z")))),
            behavior: BehaviorSettings(pollInterval: 30, showOnlyMine: true)
        )

        let data = try ProfileCodec.encode(profile)
        let decoded = try ProfileCodec.decode(data)

        XCTAssertEqual(decoded, profile)
        XCTAssertFalse(decoded.collections[1].enabled)
        // JSON legible y estable (claves ordenadas) para exportar.
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""asana""#), text)
        XCTAssertTrue(text.contains(#""version" : 2"#), text)
    }

    func testProfileCodecSaveAndLoad() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let url = tempDir.appendingPathComponent("Notchwatch/profile.json")
        let profile = NotchwatchProfile(sources: [.asana(AsanaPresets.tubuencamino)])

        try ProfileCodec.save(profile, to: url)

        XCTAssertEqual(ProfileCodec.load(from: url), profile)
        XCTAssertNil(ProfileCodec.load(from: tempDir.appendingPathComponent("no-existe.json")))
    }

    func testCorruptProfileLoadsAsNil() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let url = tempDir.appendingPathComponent("profile.json")
        try Data("{no".utf8).write(to: url)
        XCTAssertNil(ProfileCodec.load(from: url))
    }
}
