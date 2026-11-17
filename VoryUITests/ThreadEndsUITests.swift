import XCTest

/// The thread's two ends hold still (#704): a reopened long chat flung to its top shows its first message whole, under
/// the header and not cut by it; and a thread at rest mid-way doesn't move by itself after a finger's scroll stops.
/// They guard the fault #704 fixed: the stack sat centered in a content that held a height the stack no longer had,
/// so the first message could be cut under the header at the top, a band or a cut row could show at the end, and a
/// row could move a moment after the finger let go, or at the next touch. They read at rest, not during a scroll's
/// glide.
///
/// Read by frames through accessibility, as ChatsEdgeUITests reads them; no reader is compiled into the app for this.
/// Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set: the repo's mock gateway (Tools/mock-gateway/mock_gateway.py)
/// started with MOCK_TALL=near, which gives its seeded chat a long history of tall replies and tables.
@MainActor
final class ThreadEndsUITests: XCTestCase {
    private var app: XCUIApplication!

    private var env: (String, String)? {
        let e = ProcessInfo.processInfo.environment
        guard let u = e["HERMES_E2E_URL"], let t = e["HERMES_E2E_TOKEN"], !u.isEmpty, !t.isEmpty else { return nil }
        return (u, t)
    }

    /// The mock's seeded chat, which MOCK_TALL=near fills with one reply near 7,700 pt at a narrow 382 pt width,
    /// wrapped tables, a wrapped code block, and more than 96 rows.
    private let longChat = "Disk cleanup on the log host"

    /// As ChatsEdgeUITests launches: the demo copy unless HERMES_E2E_BUNDLE names another, pointed at the gateway, on
    /// the chat list, with no chat restored between the launch and the list.
    private func launch(url: String, token: String) {
        let e = ProcessInfo.processInfo.environment
        app = XCUIApplication(bundleIdentifier: e["HERMES_E2E_BUNDLE"].flatMap { $0.isEmpty ? nil : $0 } ?? "com.vorantx.vory.demo")
        app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES", "-launchTab", "chats",
                               "-restore.openChat", "none"]
        app.launch()
    }

    private func hittable(_ query: XCUIElementQuery, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let e = query.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) { return e }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return nil
    }

    private func wait(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    /// Every message row, by the prefix every row's identifier has (`thread.row.<kind>`, TranscriptView's `rowView`).
    private var rows: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "thread.row."))
    }

    /// The chat's header, whose bottom is where the thread's first row may start.
    private var header: XCUIElement { app.descendants(matching: .any).matching(identifier: "chat.header").firstMatch }
    /// Opens the long chat, goes back, and opens it again: the reopen, from the rows this device kept (state B).
    private func reopenLongChat() throws {
        let row = try XCTUnwrap(hittable(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", longChat)), timeout: 20),
                                "the long chat isn't in the list")
        row.tap()
        XCTAssertNotNil(hittable(rows, timeout: 20), "the long chat showed no row")
        try XCTUnwrap(hittable(app.descendants(matching: .any).matching(identifier: "chat.back"), timeout: 10), "no back button").tap()
        wait(1)
        try XCTUnwrap(hittable(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", longChat)), timeout: 10)).tap()
        XCTAssertNotNil(hittable(rows, timeout: 20), "the reopened chat showed no row")
        wait(1)
    }

    /// Flung to its top, the reopened chat's first row starts at the header's bottom or below it, whole.
    func testReopenFlungToTopShowsFirstRow() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        try reopenLongChat()
        let thread = app.scrollViews.firstMatch
        for _ in 0..<12 { thread.swipeDown(velocity: .fast) }
        wait(1.5)
        let first = try XCTUnwrap(rows.allElementsBoundByIndex.first(where: { $0.exists }), "no row at the top")
        // No header found would read as a bottom of 0, and a cut row would pass.
        XCTAssertTrue(header.exists, "the chat's header isn't there to read the first row against")
        let headerBottom = header.frame.maxY
        XCTAssertGreaterThanOrEqual(first.frame.minY, headerBottom - 1,
                                    "the first message starts \(headerBottom - first.frame.minY) pt under the header")
    }

    /// Mid-way, a finger's scroll comes to rest and the thread then stays where it stopped: one row's frame read at
    /// the rest and a second later differs by no more than a point.
    func testNoMoveAfterAScrollStops() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        try reopenLongChat()
        let thread = app.scrollViews.firstMatch
        for _ in 0..<3 { thread.swipeDown() }
        wait(0.8)   // the deceleration ends; the scroll's rest is when the content is sized again
        // Held by its own words, not by its place in the list: a lazy list that lays or drops rows meanwhile shifts the
        // places, and a row found by index could then be another one. A row is a group (`children: .contain`), so it has
        // no words of its own: it is held by the words of one of its first texts that no other row has (a bot's name or a
        // time can be on many rows), and found again as the one row that contains them. The row nearest the window's
        // middle that has such words is the one held, however tall it is.
        let middle = app.windows.firstMatch.frame.midY
        let inSight = rows.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
            .sorted { abs($0.frame.midY - middle) < abs($1.frame.midY - middle) }
        XCTAssertFalse(inSight.isEmpty, "no row in sight")
        var held: (words: String, at: CGRect)?
        for candidate in inSight where held == nil {
            for text in candidate.staticTexts.allElementsBoundByIndex.prefix(4) where held == nil && text.exists && !text.label.isEmpty {
                if rows.containing(NSPredicate(format: "label == %@", text.label)).count == 1 { held = (text.label, candidate.frame) }
            }
        }
        let (words, at) = try XCTUnwrap(held, "no row in sight has words of its own to hold it by")
        wait(1)
        let row = rows.containing(NSPredicate(format: "label == %@", words)).firstMatch
        XCTAssertTrue(row.exists, "the row in sight is gone a second after the scroll stopped")
        XCTAssertEqual(row.frame.minY, at.minY, accuracy: 1, "the thread moved \(row.frame.minY - at.minY) pt by itself after the scroll stopped")
    }
}
