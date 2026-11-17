import SwiftUI
import Testing
@testable import Vory

#if os(iOS)
/// 58: the top bar's measured positions, as `measured` sets them (`MorphMeasure.animates`). A changed measure of a frame
/// that had an old one animates only with the scene active; inactive or in the background it is set at once, so a fold
/// made with the app away comes back laid out, with nothing drawn from the row it had before.
@Suite struct MorphMeasureAnimatesTests {
    /// Unchanged: in front, a changed measure of a frame with an old one animates (the morph, a tab switch, a fold).
    @Test func aChangeInFrontAnimates() {
        #expect(MorphMeasure.animates(changed: true, hadOld: true, phase: .active))
    }

    /// 58: the return's first measure comes while the scene is still inactive. It is set at once.
    @Test func aChangeWhileInactiveIsSetAtOnce() {
        #expect(!MorphMeasure.animates(changed: true, hadOld: true, phase: .inactive))   // 57: animated
    }

    /// 58: a measure the background's snapshot pass makes is set at once too.
    @Test func aChangeInTheBackgroundIsSetAtOnce() {
        #expect(!MorphMeasure.animates(changed: true, hadOld: true, phase: .background)) // 57: animated
    }

    /// Unchanged: a slot's first measure is set at once, in every phase.
    @Test(arguments: [ScenePhase.active, .inactive, .background])
    func aFirstMeasureIsSetAtOnce(phase: ScenePhase) {
        #expect(!MorphMeasure.animates(changed: true, hadOld: false, phase: phase))
    }

    /// Unchanged: a measure that didn't change sets nothing to animate, in every phase.
    @Test(arguments: [ScenePhase.active, .inactive, .background])
    func noChangeNeverAnimates(phase: ScenePhase) {
        #expect(!MorphMeasure.animates(changed: false, hadOld: true, phase: phase))
    }
}
#endif
