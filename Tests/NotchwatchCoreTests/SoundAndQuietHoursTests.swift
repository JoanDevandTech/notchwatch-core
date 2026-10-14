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

final class SoundPolicyTests: XCTestCase {
    private let nightQuiet = QuietHours(enabled: true, startMinute: 22 * 60, endMinute: 8 * 60)

    func testDefaultPolicy() {
        let policy = SoundPolicy.default
        XCTAssertFalse(policy.muted)
        XCTAssertEqual(policy.quietHours, QuietHours())
        XCTAssertFalse(policy.quietHours.enabled)
        XCTAssertEqual(policy.urgentRepeatInterval, 30)
    }

    func testSoundKindOutsideQuietHours() throws {
        let calendar = try madridCalendar()
        let policy = SoundPolicy(quietHours: nightQuiet)
        let noon = try october14(12, in: calendar)
        XCTAssertEqual(policy.sound(for: .urgente, at: noon, calendar: calendar), .urgent)
        XCTAssertEqual(policy.sound(for: .alta, at: noon, calendar: calendar), .urgent)
        XCTAssertEqual(policy.sound(for: .media, at: noon, calendar: calendar), .soft)
        XCTAssertEqual(policy.sound(for: .baja, at: noon, calendar: calendar), .soft)
        XCTAssertEqual(policy.sound(for: .ninguna, at: noon, calendar: calendar), .soft)
    }

    func testOnlyUrgentSoundsDuringQuietHours() throws {
        let calendar = try madridCalendar()
        let policy = SoundPolicy(quietHours: nightQuiet)
        // Excepción: urgente suena aun en horas de silencio; alta no.
        XCTAssertEqual(policy.sound(for: .urgente, at: try october14(23, 30, in: calendar), calendar: calendar), .urgent)
        XCTAssertEqual(policy.sound(for: .urgente, at: try october14(3, in: calendar), calendar: calendar), .urgent)
        XCTAssertNil(policy.sound(for: .alta, at: try october14(23, 30, in: calendar), calendar: calendar))
        XCTAssertNil(policy.sound(for: .media, at: try october14(2, in: calendar), calendar: calendar))
        XCTAssertNil(policy.sound(for: .baja, at: try october14(7, 59, in: calendar), calendar: calendar))
        XCTAssertNil(policy.sound(for: .ninguna, at: try october14(22, in: calendar), calendar: calendar))
        // A las 08:00 termina el silencio.
        XCTAssertEqual(policy.sound(for: .alta, at: try october14(8, in: calendar), calendar: calendar), .urgent)
    }

    func testDisabledQuietHoursPlayNormallyAtNight() throws {
        let calendar = try madridCalendar()
        var quiet = nightQuiet
        quiet.enabled = false
        let policy = SoundPolicy(quietHours: quiet)
        XCTAssertEqual(policy.sound(for: .media, at: try october14(23, 30, in: calendar), calendar: calendar), .soft)
        XCTAssertEqual(policy.sound(for: .alta, at: try october14(23, 30, in: calendar), calendar: calendar), .urgent)
    }

    func testTwoArgumentVariantUsesCurrentCalendar() throws {
        // `sound(for:at:)` evalúa con Calendar.current: las fechas se construyen con él.
        let current = Calendar.current
        let policy = SoundPolicy(quietHours: nightQuiet)
        XCTAssertNil(policy.sound(for: .alta, at: try october14(23, 30, in: current)))
        XCTAssertEqual(policy.sound(for: .urgente, at: try october14(23, 30, in: current)), .urgent)
        XCTAssertEqual(policy.sound(for: .media, at: try october14(12, in: current)), .soft)
    }

    func testMutedSilencesEverything() throws {
        let calendar = try madridCalendar()
        let policy = SoundPolicy(quietHours: nightQuiet, muted: true)
        for priority in IncidentPriority.allCases {
            XCTAssertNil(policy.sound(for: priority, at: try october14(12, in: calendar), calendar: calendar))
            XCTAssertNil(policy.sound(for: priority, at: try october14(23, in: calendar), calendar: calendar))
            XCTAssertFalse(policy.shouldRepeat(for: priority))
        }
    }

    func testShouldRepeatOnlyLoud() {
        let policy = SoundPolicy.default
        XCTAssertTrue(policy.shouldRepeat(for: .urgente))
        XCTAssertTrue(policy.shouldRepeat(for: .alta))
        XCTAssertFalse(policy.shouldRepeat(for: .media))
        XCTAssertFalse(policy.shouldRepeat(for: .baja))
        XCTAssertFalse(policy.shouldRepeat(for: .ninguna))
    }

    func testCodableRoundTrip() throws {
        let policy = SoundPolicy(quietHours: nightQuiet, urgentRepeatInterval: 45, muted: true)
        let data = try JSONEncoder().encode(policy)
        XCTAssertEqual(try JSONDecoder().decode(SoundPolicy.self, from: data), policy)
        XCTAssertEqual(SoundKind(rawValue: "urgent"), .urgent)
        XCTAssertEqual(SoundKind.soft.rawValue, "soft")
    }
}
