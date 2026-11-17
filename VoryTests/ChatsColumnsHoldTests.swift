import SwiftUI
import Testing
@testable import Vory

#if os(iOS)
/// #537 and 58: the Chats split view's columns across a trip to the background, as the page plays them
/// (`ChatsSplitPage.columnsOnPhase` and `takesSplitWrite`). Held when the scene leaves wide, let go when it is active again
/// whatever is on screen, put back only on a wide return.
@Suite struct ChatsColumnsHoldTests {
    typealias V = NavigationSplitViewVisibility
    struct Page { var columns: V; var held: V? = nil; var wide: Bool }

    /// One phase change as the page meets it. A step that turns the page narrow brings the one-column branch, whose
    /// onAppear sets two columns (#547); then the rule runs.
    func step(_ p: inout Page, _ phase: ScenePhase, wide: Bool) {
        if p.wide && !wide { p.columns = .doubleColumn }
        p.wide = wide
        let next = ChatsSplitPage.columnsOnPhase(phase, wide: wide, columns: p.columns, held: p.held)
        p.columns = next.columns; p.held = next.held
    }

    /// A write of the split view's own (its collapse, the sidebar button), taken or dropped as the binding does.
    func splitWrites(_ p: inout Page, _ v: V) { if ChatsSplitPage.takesSplitWrite(held: p.held) { p.columns = v } }

    /// The scene leaves: inactive, then the background, on the window it is on.
    func leave(_ p: inout Page) {
        let w = p.wide
        step(&p, .inactive, wide: w); step(&p, .background, wide: w)
    }

    /// #537: on its side, away, back on its side. The snapshot pass's collapse is dropped; the columns come back.
    @Test func theSameWideWindowGetsItsColumnsBack() {
        var p = Page(columns: .all, wide: true)
        leave(&p)
        #expect(p.held == .all)
        splitWrites(&p, .detailOnly)
        step(&p, .inactive, wide: true); step(&p, .active, wide: true)
        #expect(p.columns == .all); #expect(p.held == nil)
    }

    /// #537: a list the person hid before leaving is still hidden on the same window.
    @Test func aHiddenListStaysHiddenOnTheSameWindow() {
        var p = Page(columns: .detailOnly, wide: true)
        leave(&p); step(&p, .inactive, wide: true); step(&p, .active, wide: true)
        #expect(p.columns == .detailOnly); #expect(p.held == nil)
    }

    /// 58: on its side with a chat open, folded closed while away. The return is narrow; the hold goes at active.
    @Test func aNarrowReturnLetsTheHoldGo() {
        var p = Page(columns: .all, wide: true)
        leave(&p)
        step(&p, .inactive, wide: false)
        #expect(p.held == .all)                    // still held until active
        step(&p, .active, wide: false)
        #expect(p.held == nil)                     // 57: .all, never let go
        #expect(p.columns == .doubleColumn)
    }

    /// 58: then unfolded onto its side, in front. Hide Sidebar is taken, so #555's rule sees the list hidden.
    @Test func theNextWideWindowTakesTheSidebarButton() {
        var p = Page(columns: .all, wide: true)
        leave(&p); step(&p, .inactive, wide: false); step(&p, .active, wide: false)
        p.wide = true                              // the unfold, in front: no phase change
        splitWrites(&p, .detailOnly)               // Hide Sidebar
        #expect(p.columns == .detailOnly)          // 57: .doubleColumn, the write dropped
    }

    /// 58: a narrow return drops the held columns rather than putting them back (#547's two columns stand).
    @Test func aNarrowReturnDropsTheHeldColumns() {
        var p = Page(columns: .detailOnly, wide: true)
        leave(&p); step(&p, .inactive, wide: false); step(&p, .active, wide: false)
        #expect(p.columns == .doubleColumn)        // a put-back form: .detailOnly
        #expect(p.held == nil)                     // 57: .detailOnly
    }

    /// Unchanged: leaving narrow (upright, or closed) holds nothing, whatever the return.
    @Test func aNarrowDepartureHoldsNothing() {
        for back in [false, true] {
            var p = Page(columns: .doubleColumn, wide: false)
            leave(&p)
            #expect(p.held == nil)
            step(&p, .inactive, wide: back); step(&p, .active, wide: back)
            #expect(p.columns == .doubleColumn); #expect(p.held == nil)
        }
    }

    /// Unchanged: a trip that never reaches the background (the switcher, Control Center) holds nothing.
    @Test func anInactiveTripHoldsNothing() {
        var p = Page(columns: .all, wide: true)
        step(&p, .inactive, wide: true); step(&p, .active, wide: true)
        #expect(p.columns == .all); #expect(p.held == nil)
    }

    /// Unchanged: a second background before active keeps the first hold; writes are taken only with none held.
    @Test func theFirstHoldIsKeptAndWritesWaitForItsRelease() {
        let r = ChatsSplitPage.columnsOnPhase(.background, wide: true, columns: .detailOnly, held: .all)
        #expect(r.held == .all); #expect(r.columns == .detailOnly)
        #expect(ChatsSplitPage.takesSplitWrite(held: nil))
        #expect(!ChatsSplitPage.takesSplitWrite(held: .all))
    }
}
#endif
