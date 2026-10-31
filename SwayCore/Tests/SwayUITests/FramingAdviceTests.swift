import CoreGraphics
import SwayModels
import Testing

@testable import SwayUI

@Suite("Framing advice")
struct FramingAdviceTests {
    /// A face box with the given size, centered unless `center` says otherwise.
    private func advice(height: CGFloat = 0.4, center: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> FramingAdvice {
        let bounds = CGRect(
            x: center.x - height / 2, y: center.y - height / 2, width: height, height: height)
        return FramingAdvice(Fixtures.pose(faceBounds: bounds))
    }

    @Test func noPoseMeansNoFace() {
        #expect(FramingAdvice(nil) == .noFace)
        #expect(FramingAdvice.noFace.text == "Gander can't see your face yet.")
    }

    @Test func aFaceThatIsTooSmallAsksToMoveCloser() {
        #expect(advice(height: 0.1) == .closer)
        #expect(advice(height: 0.179) == .closer)
        #expect(FramingAdvice.closer.text == "Move a little closer to the camera.")
    }

    @Test func aFaceThatIsTooBigAsksToMoveBack() {
        #expect(advice(height: 0.601) == .back)
        #expect(advice(height: 0.9) == .back)
        #expect(FramingAdvice.back.text == "Move back a little.")
    }

    @Test func theHeightBoundariesThemselvesAreFine() {
        #expect(advice(height: 0.18) == .good)
        #expect(advice(height: 0.6) == .good)
    }

    @Test func aFaceOffCenterOnEitherAxisAsksToCenter() {
        #expect(advice(center: CGPoint(x: 0.19, y: 0.5)) == .center)
        #expect(advice(center: CGPoint(x: 0.81, y: 0.5)) == .center)
        #expect(advice(center: CGPoint(x: 0.5, y: 0.19)) == .center)
        #expect(advice(center: CGPoint(x: 0.5, y: 0.81)) == .center)
        #expect(FramingAdvice.center.text == "Center your face in the camera's view.")
    }

    @Test func justInsideTheCenterRangeIsFineAndJustOutsideIsNot() {
        #expect(advice(height: 0.2, center: CGPoint(x: 0.2001, y: 0.5)) == .good)
        #expect(advice(height: 0.2, center: CGPoint(x: 0.5, y: 0.2001)) == .good)
        #expect(advice(height: 0.2, center: CGPoint(x: 0.7999, y: 0.7999)) == .good)
        #expect(advice(height: 0.2, center: CGPoint(x: 0.1999, y: 0.5)) == .center)
        #expect(advice(height: 0.2, center: CGPoint(x: 0.5, y: 0.8001)) == .center)
        #expect(FramingAdvice.centerRange == 0.2...0.8)
    }

    @Test func aWellFramedFaceLooksGood() {
        #expect(advice() == .good)
        #expect(FramingAdvice.good.text == "Looks good.")
    }

    @Test func theSizeRulesComeBeforeTheCenterRule() {
        #expect(advice(height: 0.1, center: CGPoint(x: 0.05, y: 0.5)) == .closer)
        #expect(advice(height: 0.7, center: CGPoint(x: 0.9, y: 0.5)) == .back)
    }
}
