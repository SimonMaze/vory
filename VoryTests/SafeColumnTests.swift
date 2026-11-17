#if os(iOS)
import CoreGraphics
import Testing
@testable import Vory

/// The widest a thread's column may be in its window (`SafeColumn.width`): the window's width less its side insets, or
/// no limit while the window has no width to give.
@Suite struct SafeColumnTests {
    /// The closed iPhone Duo: a 466 pt window with its side strip's 84 pt of insets gives the 382 pt safe width.
    @Test func theClosedDuoGivesItsSafeWidth() {
        #expect(SafeColumn.width(window: 466, leading: 84, trailing: 0) == 382)
    }

    /// The insets count on either side, and on both.
    @Test func eitherSideCounts() {
        #expect(SafeColumn.width(window: 466, leading: 0, trailing: 84) == 382)
        #expect(SafeColumn.width(window: 466, leading: 42, trailing: 42) == 382)
    }

    /// A phone with no side insets: the whole window, which a column of that width never exceeds.
    @Test func noSideInsetsIsTheWholeWindow() {
        #expect(SafeColumn.width(window: 402, leading: 0, trailing: 0) == 402)
    }

    /// A window not yet laid out gives no limit.
    @Test func noWindowIsNoLimit() {
        #expect(SafeColumn.width(window: 0, leading: 0, trailing: 0) == .infinity)
    }

    /// Insets that leave nothing give no limit, rather than a column of no width.
    @Test func insetsThatLeaveNothingAreNoLimit() {
        #expect(SafeColumn.width(window: 80, leading: 40, trailing: 40) == .infinity)
        #expect(SafeColumn.width(window: 80, leading: 60, trailing: 40) == .infinity)
    }

    /// A negative inset is taken as none.
    @Test func aNegativeInsetIsNone() {
        #expect(SafeColumn.width(window: 466, leading: -10, trailing: 84) == 382)
    }
}
#endif
