import Foundation
import XCTest
@testable import NotchwatchCore

final class ConsoleSummaryParserTests: XCTestCase {
    func testParsesBasicFormat() {
        XCTAssertEqual(ConsoleSummaryParser.errorCount(fromNotes: "Errores consola: 7/10"), 7)
    }

    func testParsesInsideLongNotes() {
        let notes = "Pasos:\n1. Abrir\n\nResumen\nURL: /x\nErrores consola: 12/40\nNavegador: Safari"
        XCTAssertEqual(ConsoleSummaryParser.errorCount(fromNotes: notes), 12)
    }

    func testParsesVariants() {
        XCTAssertEqual(ConsoleSummaryParser.errorCount(fromNotes: "**Errores consola:** 0/5"), 0)
        XCTAssertEqual(ConsoleSummaryParser.errorCount(fromNotes: "**Errores consola**: 4/4"), 4)
        XCTAssertEqual(ConsoleSummaryParser.errorCount(fromNotes: "errores de consola:3/9"), 3)
        XCTAssertEqual(ConsoleSummaryParser.errorCount(fromNotes: "Errores de consola: 2/2"), 2)
        XCTAssertEqual(ConsoleSummaryParser.errorCount(fromNotes: "ERRORES CONSOLA: 2"), 2)
        XCTAssertEqual(ConsoleSummaryParser.errorCount(fromNotes: "Errores consola:   15 / 20"), 15)
    }

    func testIgnoresOtherNumbersBeforeTheSummary() {
        let notes = "Reserva 4521, 3 huéspedes.\nErrores consola: 1/8"
        XCTAssertEqual(ConsoleSummaryParser.errorCount(fromNotes: notes), 1)
    }

    func testReturnsNilWithoutSummary() {
        XCTAssertNil(ConsoleSummaryParser.errorCount(fromNotes: nil))
        XCTAssertNil(ConsoleSummaryParser.errorCount(fromNotes: ""))
        XCTAssertNil(ConsoleSummaryParser.errorCount(fromNotes: "Sin errores reseñables"))
        XCTAssertNil(ConsoleSummaryParser.errorCount(fromNotes: "Errores consola: n/a"))
        XCTAssertNil(ConsoleSummaryParser.errorCount(fromNotes: "Errores de red: 3/4"))
    }
}
