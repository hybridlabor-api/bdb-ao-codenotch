import XCTest
@testable import Codenotch

/// Same measurement as `Codenotch --bdb-selftest` (which runs without Xcode).
@MainActor
final class BDBPopoverHeightTests: XCTestCase {
    func testCardFitsContentAtOneThreeFourAndSixRows() {
        var last: CGFloat = 0
        for n in [1, 3, 4, 6] {
            let m = BDBPopoverFit.measure(rows: n, pngDir: nil)
            XCTAssertGreaterThanOrEqual(m.card, m.fitting - 0.5, "\(n) rows: card clips its content")
            XCTAssertLessThanOrEqual(m.card, m.fitting + 6, "\(n) rows: card has excess slack")
            XCTAssertGreaterThan(m.card, last, "height must grow with rows")
            last = m.card
        }
    }

    func testCardFitsCodexGroupedWindows() {
        for groups in [0, 2] {
            let m = BDBPopoverFit.measure(snapshot: BDBPopoverFit.codexSnapshot(groups: groups), pngDir: nil)
            XCTAssertGreaterThanOrEqual(m.card, m.fitting - 0.5, "\(groups) groups: card clips its content")
            XCTAssertLessThanOrEqual(m.card, m.fitting + 6, "\(groups) groups: card has excess slack")
        }
    }

    func testPopoverHasNoAORowAndOnlyTheUpdateHint() {
        let s = BDBPopoverFit.snapshot(agentRows: 3)
        XCTAssertFalse(s.windows.contains { $0.label == "AO" })
        XCTAssertEqual(s.windows.first { $0.id == "ver-AOS" }?.note, "update available: 4.18.1")
        XCTAssertNil(BDBPopoverFit.snapshot(agentRows: 3, update: false).windows.first { $0.id == "ver-AOS" }?.note)
    }
}
