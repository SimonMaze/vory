#if os(iOS)
import CoreGraphics
import Testing
@testable import Vory

/// The thread's distance from its end by UIKit's own figures (`ScrollTruth.distance`), taken in place of SwiftUI's last
/// report after the quiet sizing: nothing when the two agree within half a point, else the end's settle's sum.
@Suite struct ScrollTruthTests {
    /// UIKit's figures beside a report, with a window of 678 pt and a bottom inset of 140 pt.
    static func distance(_ height: CGFloat, _ offset: CGFloat, reported: (CGFloat, CGFloat)) -> CGFloat? {
        ScrollTruth.distance(height: height, offset: offset, bottomInset: 140, boundsHeight: 678,
                             reportedHeight: reported.0, reportedOffset: reported.1)
    }

    /// A report left short of UIKit after a sizing that changed nothing: UIKit at its own end reads as at the end.
    @Test func aStaleReportGivesWayToUIKitsEnd() throws {
        let d = try #require(Self.distance(8598.33, 8060.33, reported: (8582, 7987.33)))
        #expect(abs(d) < 0.01)
    }

    /// The two agree: nothing is written.
    @Test func agreeingFiguresWriteNothing() {
        #expect(Self.distance(8598.33, 8060.33, reported: (8598.33, 8060.33)) == nil)
    }

    /// Within half a point on both: nothing is written.
    @Test func halfAPointIsAgreement() {
        #expect(Self.distance(8598.33, 8060.33, reported: (8598.0, 8060.0)) == nil)
    }

    /// The offset alone differs: the distance is UIKit's, here a thread 100 pt up from its end.
    @Test func anOffsetAloneIsEnough() throws {
        let d = try #require(Self.distance(8598.33, 7960.33, reported: (8598.33, 8060.33)))
        #expect(abs(d - 100) < 0.01)
    }

    /// The height alone differs by more than half a point: the distance is UIKit's.
    @Test func aHeightAloneIsEnough() throws {
        let d = try #require(Self.distance(8599.33, 8060.33, reported: (8598.33, 8060.33)))
        #expect(abs(d - 1) < 0.01)
    }
}
#endif
