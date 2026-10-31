import Foundation
import Testing

@testable import GanderUI

@Suite("Face debounce")
struct FaceDebounceTests {
    /// Feeds one sample and returns whether a face counts as present afterwards.
    private func update(_ debounce: inout FaceDebounce, face: Bool, at timestamp: TimeInterval) -> Bool {
        debounce.update(face: face, at: timestamp)
    }

    @Test func aFaceShowsAtOnce() {
        var debounce = FaceDebounce()
        #expect(!debounce.isPresent)

        let present = update(&debounce, face: true, at: 10)

        #expect(present)
        #expect(debounce.isPresent)
    }

    @Test func noFaceShowsOnlyAfterHalfASecondWithoutOne() {
        var debounce = FaceDebounce()
        _ = update(&debounce, face: true, at: 10)

        let oneFrameLater = update(&debounce, face: false, at: 10.2)
        let justBefore = update(&debounce, face: false, at: 10.49)
        let atTheDelay = update(&debounce, face: false, at: 10.5)
        let later = update(&debounce, face: false, at: 11)

        #expect(oneFrameLater, "Still the face")
        #expect(justBefore)
        #expect(!atTheDelay, "Half a second after the last face")
        #expect(!later)
    }

    @Test func aFaceInBetweenStartsTheWaitAgain() {
        var debounce = FaceDebounce()
        _ = update(&debounce, face: true, at: 10)
        _ = update(&debounce, face: false, at: 10.4)
        _ = update(&debounce, face: true, at: 10.45)

        let stillWithin = update(&debounce, face: false, at: 10.9)
        let past = update(&debounce, face: false, at: 10.95)

        #expect(stillWithin, "0.45 s after the face that came back")
        #expect(!past)
    }

    @Test func aFaceComingBackAfterNoFaceShowsAtOnce() {
        var debounce = FaceDebounce()
        _ = update(&debounce, face: true, at: 1)
        _ = update(&debounce, face: false, at: 2)
        #expect(!debounce.isPresent)

        let back = update(&debounce, face: true, at: 2.07)

        #expect(back)
    }

    @Test func noFaceFromTheStartStaysAbsent() {
        var debounce = FaceDebounce()

        let first = update(&debounce, face: false, at: 1)
        let later = update(&debounce, face: false, at: 5)

        #expect(!first)
        #expect(!later)
    }

    @Test func aClockThatRestartsLowerDoesNotPinTheFace() {
        var debounce = FaceDebounce()
        _ = update(&debounce, face: true, at: 500)

        let firstAfterRestart = update(&debounce, face: false, at: 3)
        let half = update(&debounce, face: false, at: 3.5)

        #expect(firstAfterRestart)
        #expect(!half)
    }

    @Test func resetForgetsTheFace() {
        var debounce = FaceDebounce()
        _ = update(&debounce, face: true, at: 10)

        debounce.reset()
        let after = update(&debounce, face: false, at: 10.1)

        #expect(!debounce.isPresent)
        #expect(!after)
    }
}
