import Foundation
import XCTest
#if canImport(KUSCCore)
@testable import KUSCCore
#else
@testable import KUSC_SE
#endif

final class BufferScrubTests: XCTestCase {
    private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
    private func window(_ oldest: TimeInterval, _ live: TimeInterval) -> BufferWindow {
        BufferWindow(oldest: date(oldest), live: date(live))
    }

    func testDragBeforeRetentionFillsReleasesItsOldCoordinateRange() {
        var scrub = BufferScrubState()
        scrub.begin(in: window(0, 45))
        XCTAssertNil(scrub.update(date(20), currentWindow: window(0, 50)))
        XCTAssertEqual(scrub.frozenWindow, window(0, 45))
        XCTAssertEqual(scrub.end(), .seek(date(20)))
        XCTAssertNil(scrub.frozenWindow)
        XCTAssertNil(scrub.preview)
        // A second drag must see newly acquired history, not the first range.
        scrub.begin(in: window(0, 180))
        XCTAssertEqual(scrub.frozenWindow?.duration, 180)
        XCTAssertNil(scrub.update(date(90), currentWindow: window(0, 181)))
        XCTAssertEqual(scrub.end(), .seek(date(90)))
    }

    func testFinalNativeValueAfterEditingEndDoesNotRefreezeOrSeekTwice() {
        var scrub = BufferScrubState()
        scrub.begin(in: window(0, 60))
        _ = scrub.update(date(25), currentWindow: window(0, 61))
        XCTAssertEqual(scrub.end(), .seek(date(25)))
        XCTAssertNil(scrub.update(date(25), currentWindow: window(0, 62)))
        XCTAssertFalse(scrub.isEditing)
        XCTAssertNil(scrub.preview)
        XCTAssertNil(scrub.frozenWindow)
    }

    func testNonTouchAdjustmentCommitsWithoutWaitingForEditingEnd() {
        var scrub = BufferScrubState()
        XCTAssertEqual(scrub.update(date(40), currentWindow: window(0, 60)), .seek(date(40)))
        XCTAssertFalse(scrub.isEditing)
        XCTAssertNil(scrub.preview)
        XCTAssertEqual(scrub.update(date(100), currentWindow: window(0, 140)), .seek(date(100)))
        XCTAssertNil(scrub.frozenWindow)
    }

    func testRightEdgeStillUsesLiveAfterHistoryGrowsDuringDrag() {
        var scrub = BufferScrubState()
        scrub.begin(in: window(0, 60))
        _ = scrub.update(date(60), currentWindow: window(0, 65))
        XCTAssertEqual(scrub.end(), .live)
        XCTAssertNil(scrub.update(date(60), currentWindow: window(0, 66)))
        XCTAssertFalse(scrub.isEditing)
    }

    func testCancelledDragDoesNotCommitAndNextAdjustmentUsesCurrentRetention() {
        var scrub = BufferScrubState()
        scrub.begin(in: window(0, 60))
        _ = scrub.update(date(10), currentWindow: window(0, 70))
        scrub.cancel()
        XCTAssertNil(scrub.end())
        XCTAssertNil(scrub.preview)
        XCTAssertEqual(scrub.update(date(10), currentWindow: window(40, 340)), .seek(date(40)))
    }

    func testNonTrackingValueCompletesAnUnpairedEditingCallback() {
        var scrub = BufferScrubState()
        scrub.begin(in: window(0, 60))
        _ = scrub.update(date(20), currentWindow: window(0, 61))
        XCTAssertEqual(scrub.finishAdjustment(date(30), currentWindow: window(0, 62)), .seek(date(30)))
        XCTAssertFalse(scrub.isEditing)
        XCTAssertNil(scrub.preview)
        XCTAssertNil(scrub.frozenWindow)
        XCTAssertNil(scrub.end(), "A later touch-end cannot seek twice")
        scrub.begin(in: window(0, 180))
        XCTAssertEqual(scrub.frozenWindow?.duration, 180)
    }

    func testNonTrackingRightEdgeCompletesUsingTheFrozenDragRange() {
        var scrub = BufferScrubState()
        scrub.begin(in: window(0, 60))
        _ = scrub.update(date(55), currentWindow: window(0, 65))
        XCTAssertEqual(scrub.finishAdjustment(date(60), currentWindow: window(0, 66)), .live)
        XCTAssertNil(scrub.finishAdjustment(date(60), currentWindow: window(0, 67)))
        XCTAssertFalse(scrub.isEditing)
        XCTAssertNil(scrub.preview)
    }
}
