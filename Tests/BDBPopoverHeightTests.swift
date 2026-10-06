import XCTest
@testable import Codenotch

/// Same measurement as `Codenotch --bdb-selftest` (which runs without Xcode).
@MainActor
final class BDBPopoverHeightTests: XCTestCase {
    func testCardFitsContentAtOneThreeAndSixRows() {
        var last: CGFloat = 0
        for n in [1, 3, 6] {
            let m = BDBPopoverFit.measure(rows: n, pngDir: nil)
            XCTAssertGreaterThanOrEqual(m.card, m.fitting - 0.5, "\(n) rows: card clips its content")
            XCTAssertLessThanOrEqual(m.card, m.fitting + 24, "\(n) rows: card has excess slack")
            XCTAssertGreaterThan(m.card, last, "height must grow with rows")
            last = m.card
        }
    }

    func testPopoverHasNoAORowAndOnlyTheUpdateHint() {
        let s = BDBPopoverFit.snapshot(agentRows: 3)
        XCTAssertFalse(s.windows.contains { $0.label == "AO" })
        XCTAssertEqual(s.windows.first { $0.id == "ver-AOS" }?.note, "update available: 4.18.1")
        XCTAssertNil(BDBPopoverFit.snapshot(agentRows: 3, update: false).windows.first { $0.id == "ver-AOS" }?.note)
    }
}
