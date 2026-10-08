import Foundation
import XCTest
#if canImport(KUSCCore)
@testable import KUSCCore
#else
@testable import KUSC_SE
#endif

final class WidgetSnapshotTests: XCTestCase {
    func testSnapshotRoundTripKeepsHeardMetadataAndArtworkTogether() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        XCTAssertNil(store.read())
        let item = ProgrammeItem(id: "heard", start: Date(), work: "Concerto", movement: "Adagio",
                                 composer: "Composer", performers: "Soloist; orchestra", programme: "Afternoon", host: "Host")
        let snapshot = WidgetPlaybackSnapshot(playbackRequested: true, item: item, artwork: Data([1, 2, 3]))
        try store.write(snapshot)
        XCTAssertEqual(store.read(), snapshot)
        var paused = snapshot; paused.playbackRequested = false
        try store.write(paused)
        XCTAssertEqual(store.read(), paused)
    }

    func testCorruptSnapshotFailsWithoutDiscardingPlayerState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        try store.write(.init())
        try Data("incomplete".utf8).write(to: directory.appendingPathComponent("playback-widget-v1.json"))
        XCTAssertNil(store.read())
    }

    func testPlayingLeaseExpiresAndPausedStateDoesNotRevive() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = WidgetPlaybackSnapshot(updatedAt: now, playbackRequested: true)
        XCTAssertTrue(snapshot.requestingPlayback(at: now.addingTimeInterval(119)))
        XCTAssertFalse(snapshot.requestingPlayback(at: now.addingTimeInterval(120)))
        XCTAssertFalse(WidgetPlaybackSnapshot(updatedAt: now).requestingPlayback(at: now))
    }

    func testPublicationDeduplicatesTimeButNotTransportOrMetadata() {
        let snapshot = WidgetPlaybackSnapshot()
        var next = snapshot; next.updatedAt = snapshot.updatedAt.addingTimeInterval(1)
        XCTAssertTrue(snapshot.hasSameContent(as: next))
        next.playbackRequested = true
        XCTAssertFalse(snapshot.hasSameContent(as: next))
        next = snapshot; next.work = "New work"
        XCTAssertFalse(snapshot.hasSameContent(as: next))
    }

    func testBoundedMetadataAndImageSize() {
        let item = ProgrammeItem(id: "long", start: Date(), work: String(repeating: "♪", count: 400),
                                 composer: String(repeating: "C", count: 300))
        let snapshot = WidgetPlaybackSnapshot(item: item, artwork: Data(repeating: 0, count: 120_001))
        XCTAssertEqual(snapshot.work.count, 240)
        XCTAssertEqual(snapshot.composer.count, 160)
        XCTAssertNil(snapshot.artwork)
    }

    func testResignedGroupsStayWithinThisAppProfile() {
        let group = "group.org.personal.kusc.modern.widgets"
        XCTAssertEqual(WidgetPlaybackSnapshot.groupIdentifiers(configured: group, resigned: [
            "group.org.personal.kusc.classic.widgets.TEAM", group + ".TEAM", group + "unrelated"
        ]), [group + ".TEAM", group])
    }
}
