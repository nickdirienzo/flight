import XCTest
@testable import FlightCore

/// Tests for `ChatSection.paginationStart` — the pure pagination math
/// that drives `ChatMessageListView.visibleSections`. Each test names a
/// user-observable scenario from the chat UI.
final class ChatPaginationTests: XCTestCase {

    // MARK: - Initial open (firstShownIndex == nil)

    func testEmptyConversationRendersNothing() {
        let start = ChatSection.paginationStart(
            totalCount: 0,
            firstShownIndex: nil,
            initialVisibleCount: 150
        )
        XCTAssertEqual(start, 0)
    }

    func testShortConversationShowsAllSections() {
        // 50 < 150 → no clipping, render the whole thing.
        let start = ChatSection.paginationStart(
            totalCount: 50,
            firstShownIndex: nil,
            initialVisibleCount: 150
        )
        XCTAssertEqual(start, 0)
    }

    func testExactlyAtCapShowsAllSections() {
        // 150 == 150 → render all, no off-by-one.
        let start = ChatSection.paginationStart(
            totalCount: 150,
            firstShownIndex: nil,
            initialVisibleCount: 150
        )
        XCTAssertEqual(start, 0)
    }

    func testLongConversationCapsToTrailingWindow() {
        // 1000 sections, default cap of 150 → start at index 850.
        let start = ChatSection.paginationStart(
            totalCount: 1000,
            firstShownIndex: nil,
            initialVisibleCount: 150
        )
        XCTAssertEqual(start, 850)
        XCTAssertEqual(1000 - start, 150)
    }

    // MARK: - Streaming append (firstShownIndex stays put)

    func testStreamingAppendDoesNotSlideTheWindow() {
        // User scrolled all the way back: firstShownIndex = 0.
        // Streaming appends a new section. The window should keep its
        // left edge anchored — old context the user is reading must not
        // disappear under them.
        let beforeAppend = ChatSection.paginationStart(
            totalCount: 1000,
            firstShownIndex: 0,
            initialVisibleCount: 150
        )
        let afterAppend = ChatSection.paginationStart(
            totalCount: 1001,
            firstShownIndex: 0,
            initialVisibleCount: 150
        )
        XCTAssertEqual(beforeAppend, 0)
        XCTAssertEqual(afterAppend, 0)
    }

    func testStreamingAppendAtPartialBackfillStaysAnchored() {
        // User scrolled back one page: window is sections[700...] of 1000.
        // Streaming adds 5 new sections. Left edge stays at 700 — window
        // grows from 300 to 305 visible, all at the bottom.
        let before = ChatSection.paginationStart(
            totalCount: 1000,
            firstShownIndex: 700,
            initialVisibleCount: 150
        )
        let after = ChatSection.paginationStart(
            totalCount: 1005,
            firstShownIndex: 700,
            initialVisibleCount: 150
        )
        XCTAssertEqual(before, 700)
        XCTAssertEqual(after, 700)
        XCTAssertEqual(1005 - after, 305)
    }

    // MARK: - Load more (user scrolls to top of loaded window)

    func testLoadMoreSteppingBackOnePage() {
        // Default state on a 1000-section conv: start = 850.
        // User scrolls up, sentinel fires loadMore (pageSize 150):
        // newStart = max(0, 850 - 150) = 700.
        let defaultStart = ChatSection.paginationStart(
            totalCount: 1000,
            firstShownIndex: nil,
            initialVisibleCount: 150
        )
        let newStart = max(0, defaultStart - 150)
        let afterLoadMore = ChatSection.paginationStart(
            totalCount: 1000,
            firstShownIndex: newStart,
            initialVisibleCount: 150
        )
        XCTAssertEqual(afterLoadMore, 700)
    }

    func testLoadMoreClampsAtZero() {
        // User on a 200-section conv. Default start = 50.
        // First loadMore: 50 - 150 → clamped to 0.
        let newStart = max(0, 50 - 150)
        let afterLoadMore = ChatSection.paginationStart(
            totalCount: 200,
            firstShownIndex: newStart,
            initialVisibleCount: 150
        )
        XCTAssertEqual(afterLoadMore, 0)
    }

    // MARK: - Conversation switch (firstShownIndex reset to nil)

    func testConversationSwitchReDerivesDefault() {
        // Was scrolled back on conv A (firstShownIndex = 100).
        // Switch to conv B with 50 sections — nil reset re-derives 0.
        let resetStart = ChatSection.paginationStart(
            totalCount: 50,
            firstShownIndex: nil,
            initialVisibleCount: 150
        )
        XCTAssertEqual(resetStart, 0)

        // Switch to conv C with 1000 sections — nil derives to 850.
        let resetStartLong = ChatSection.paginationStart(
            totalCount: 1000,
            firstShownIndex: nil,
            initialVisibleCount: 150
        )
        XCTAssertEqual(resetStartLong, 850)
    }

    // MARK: - Stale state guards

    func testFirstShownIndexBeyondTotalClampsToTotal() {
        // After a clearMessages (sections = []), a stale firstShownIndex
        // of 700 must not crash or return a negative slice. Clamps to
        // totalCount, which yields an empty visible window.
        let start = ChatSection.paginationStart(
            totalCount: 0,
            firstShownIndex: 700,
            initialVisibleCount: 150
        )
        XCTAssertEqual(start, 0)
    }

    func testNegativeFirstShownIndexClampsToZero() {
        // Defensive: pagination must never reach into negative slice
        // territory if a future bug ever sets a negative anchor.
        let start = ChatSection.paginationStart(
            totalCount: 1000,
            firstShownIndex: -5,
            initialVisibleCount: 150
        )
        XCTAssertEqual(start, 0)
    }

    // MARK: - Full sequence (user journey)

    func testFullJourney_OpenScrollAppendSwitch() {
        // 1. Open a 500-section conversation.
        var firstShownIndex: Int? = nil
        var totalCount = 500
        XCTAssertEqual(
            ChatSection.paginationStart(
                totalCount: totalCount,
                firstShownIndex: firstShownIndex,
                initialVisibleCount: 150
            ),
            350,
            "default cap on open"
        )

        // 2. User scrolls to top of loaded window. Sentinel fires once
        //    → newStart = 350 - 150 = 200.
        firstShownIndex = max(0, 350 - 150)
        XCTAssertEqual(
            ChatSection.paginationStart(
                totalCount: totalCount,
                firstShownIndex: firstShownIndex,
                initialVisibleCount: 150
            ),
            200,
            "after first load-more"
        )

        // 3. Streaming appends 3 sections. Anchor stays at 200.
        totalCount = 503
        XCTAssertEqual(
            ChatSection.paginationStart(
                totalCount: totalCount,
                firstShownIndex: firstShownIndex,
                initialVisibleCount: 150
            ),
            200,
            "streaming should not slide left edge"
        )

        // 4. User scrolls up again. Sentinel fires → 200 - 150 = 50.
        firstShownIndex = max(0, 200 - 150)
        XCTAssertEqual(
            ChatSection.paginationStart(
                totalCount: totalCount,
                firstShownIndex: firstShownIndex,
                initialVisibleCount: 150
            ),
            50,
            "after second load-more"
        )

        // 5. User switches conversation → firstShownIndex = nil. Land
        //    on a different conversation with 30 sections — render all.
        firstShownIndex = nil
        totalCount = 30
        XCTAssertEqual(
            ChatSection.paginationStart(
                totalCount: totalCount,
                firstShownIndex: firstShownIndex,
                initialVisibleCount: 150
            ),
            0,
            "switch resets via nil and short conv shows everything"
        )
    }
}
