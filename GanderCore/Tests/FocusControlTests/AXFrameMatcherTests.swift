import CoreGraphics
import Testing

@testable import FocusControl

@Suite struct AXFrameMatcherTests {
    private let target = CGRect(x: 100, y: 200, width: 800, height: 600)

    @Test func identicalFramesMatch() {
        #expect(AXFrameMatcher.matches(target, target))
    }

    @Test func differencesUpToTwoPointsMatch() {
        #expect(AXFrameMatcher.matches(target, CGRect(x: 102, y: 198, width: 802, height: 598)))
    }

    @Test func differencesBeyondTwoPointsDoNot() {
        #expect(!AXFrameMatcher.matches(target, CGRect(x: 102.5, y: 200, width: 800, height: 600)))
        #expect(!AXFrameMatcher.matches(target, CGRect(x: 100, y: 203, width: 800, height: 600)))
        #expect(!AXFrameMatcher.matches(target, CGRect(x: 100, y: 200, width: 797, height: 600)))
        #expect(!AXFrameMatcher.matches(target, CGRect(x: 100, y: 200, width: 800, height: 603)))
    }

    @Test func matchingIndexFindsTheMatchingWindow() {
        let candidates: [CGRect?] = [
            CGRect(x: 0, y: 0, width: 400, height: 300),
            CGRect(x: 101, y: 201, width: 799, height: 601),
        ]
        #expect(AXFrameMatcher.matchingIndex(for: target, among: candidates) == 1)
    }

    @Test func closestMatchWinsAmongSeveral() {
        let candidates: [CGRect?] = [
            CGRect(x: 102, y: 200, width: 800, height: 600),
            CGRect(x: 100, y: 201, width: 800, height: 600),
            CGRect(x: 100, y: 200, width: 800, height: 600),
        ]
        #expect(AXFrameMatcher.matchingIndex(for: target, among: candidates) == 2)
    }

    @Test func firstWinsWhenMatchesAreEquallyClose() {
        let candidates: [CGRect?] = [target, target]
        #expect(AXFrameMatcher.matchingIndex(for: target, among: candidates) == 0)
    }

    @Test func unreadableFramesAreSkipped() {
        let candidates: [CGRect?] = [nil, target]
        #expect(AXFrameMatcher.matchingIndex(for: target, among: candidates) == 1)
    }

    @Test func noMatchIsNil() {
        let candidates: [CGRect?] = [CGRect(x: 0, y: 0, width: 400, height: 300), nil]
        #expect(AXFrameMatcher.matchingIndex(for: target, among: candidates) == nil)
        #expect(AXFrameMatcher.matchingIndex(for: target, among: []) == nil)
    }

    @Test func onlyWindowIsUsedWhenNothingMatches() {
        let candidates: [CGRect?] = [CGRect(x: 0, y: 0, width: 400, height: 300)]
        #expect(AXFrameMatcher.selectedIndex(for: target, among: candidates) == 0)
        #expect(AXFrameMatcher.selectedIndex(for: target, among: [nil]) == 0)
    }

    @Test func severalNonMatchingWindowsGiveNoSelection() {
        let candidates: [CGRect?] = [
            CGRect(x: 0, y: 0, width: 400, height: 300),
            CGRect(x: 10, y: 10, width: 400, height: 300),
        ]
        #expect(AXFrameMatcher.selectedIndex(for: target, among: candidates) == nil)
        #expect(AXFrameMatcher.selectedIndex(for: target, among: []) == nil)
    }

    @Test func aFrameMatchBeatsTheSingleWindowFallback() {
        #expect(AXFrameMatcher.selectedIndex(for: target, among: [target]) == 0)
        let candidates: [CGRect?] = [CGRect(x: 0, y: 0, width: 1, height: 1), target]
        #expect(AXFrameMatcher.selectedIndex(for: target, among: candidates) == 1)
    }
}
