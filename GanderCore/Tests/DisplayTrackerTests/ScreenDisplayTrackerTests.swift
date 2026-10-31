import AppKit
import CoreGraphics
import GanderModels
import Testing

@testable import DisplayTracker

@Suite("ScreenDisplayTracker")
@MainActor
struct ScreenDisplayTrackerTests {
    private static let left = ScreenDescriptor.fixture(
        cgDisplayID: 1,
        uuid: "LEFT",
        name: "Left",
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        isMain: true
    )
    private static let right = ScreenDescriptor.fixture(
        cgDisplayID: 2,
        uuid: "RIGHT",
        name: "Right",
        frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)
    )

    private static let oneDisplay = ScreenDescriptor.layout(from: [left])
    private static let twoDisplays = ScreenDescriptor.layout(from: [left, right])

    @Test func defaultDebounceIsHalfASecond() {
        #expect(ScreenDisplayTracker.defaultDebounce == .milliseconds(500))
    }

    @Test func currentLayoutIsBuiltFromTheInjectedScreens() {
        let fixture = TrackerFixture([Self.left, Self.right])

        #expect(fixture.tracker.currentLayout == Self.twoDisplays)
        #expect(fixture.screens.readCount == 1)
    }

    @Test func layoutsYieldsTheCurrentLayoutImmediately() async {
        let fixture = TrackerFixture([Self.left])
        let collector = LayoutCollector(fixture.tracker.layouts())

        let arrived = await waitUntil { collector.layouts.count == 1 }

        #expect(arrived)
        #expect(collector.layouts.first == Self.oneDisplay)
        #expect(fixture.sleeper.startedCount == 0)
        collector.cancel()
    }

    @Test func layoutsOnTheRealTrackerYieldsAtLeastOneValue() async {
        let collector = LayoutCollector(ScreenDisplayTracker().layouts())

        let arrived = await waitUntil { !collector.layouts.isEmpty }

        #expect(arrived)
        collector.cancel()
    }

    @Test func changeIsNotReadUntilTheDebounceElapses() async {
        let fixture = TrackerFixture([Self.left])
        let collector = LayoutCollector(fixture.tracker.layouts())
        _ = await waitUntil { collector.layouts.count == 1 }
        fixture.screens.descriptors = [Self.left, Self.right]

        fixture.postScreenChange()
        let sleeping = await waitUntil { fixture.sleeper.pendingCount == 1 }
        await settle()

        #expect(sleeping)
        #expect(fixture.sleeper.lastDuration == .milliseconds(500))
        #expect(fixture.screens.readCount == 1)
        #expect(collector.layouts.count == 1)

        let delivered = await fixture.fireUntil { collector.layouts.count == 2 }

        #expect(delivered)
        #expect(collector.layouts.last == Self.twoDisplays)
        #expect(fixture.screens.readCount == 2)
        collector.cancel()
    }

    @Test func burstOfNotificationsCausesOneRecompute() async {
        let fixture = TrackerFixture([Self.left])
        let collector = LayoutCollector(fixture.tracker.layouts())
        _ = await waitUntil { collector.layouts.count == 1 }
        fixture.screens.descriptors = [Self.left, Self.right]

        for _ in 0..<5 {
            fixture.postScreenChange()
        }
        let delivered = await fixture.fireUntil { collector.layouts.count == 2 }
        await settle()
        fixture.sleeper.fireAll()
        await settle()

        #expect(delivered)
        // One read for the initial layout and exactly one for the whole burst.
        #expect(fixture.screens.readCount == 2)
        #expect(collector.layouts == [Self.oneDisplay, Self.twoDisplays])
        collector.cancel()
    }

    @Test func recomputeWithAnIdenticalLayoutIsNotYielded() async {
        let fixture = TrackerFixture([Self.left, Self.right])
        let collector = LayoutCollector(fixture.tracker.layouts())
        _ = await waitUntil { collector.layouts.count == 1 }

        fixture.postScreenChange()
        let recomputed = await fixture.fireUntil { fixture.screens.readCount == 2 }
        await settle()

        #expect(recomputed)
        #expect(collector.layouts == [Self.twoDisplays])
        collector.cancel()
    }

    @Test func eachDistinctChangeIsYieldedAndDuplicatesOfTheLastValueAreNot() async {
        let fixture = TrackerFixture([Self.left])
        let collector = LayoutCollector(fixture.tracker.layouts())
        _ = await waitUntil { collector.layouts.count == 1 }

        // Same layout again: no yield.
        fixture.postScreenChange()
        _ = await fixture.fireUntil { fixture.screens.readCount == 2 }

        // A second display appears: yield.
        fixture.screens.descriptors = [Self.left, Self.right]
        fixture.postScreenChange()
        _ = await fixture.fireUntil { collector.layouts.count == 2 }

        // Same two-display layout again: no yield.
        fixture.postScreenChange()
        _ = await fixture.fireUntil { fixture.screens.readCount == 4 }

        // Back to one display: yield, even though it equals the first value (only the last one is compared).
        fixture.screens.descriptors = [Self.left]
        fixture.postScreenChange()
        _ = await fixture.fireUntil { collector.layouts.count == 3 }
        await settle()

        #expect(collector.layouts == [Self.oneDisplay, Self.twoDisplays, Self.oneDisplay])
        collector.cancel()
    }

    @Test func aChangedCGDisplayIDForTheSameArrangementIsStillYielded() async {
        let fixture = TrackerFixture([Self.left])
        let collector = LayoutCollector(fixture.tracker.layouts())
        _ = await waitUntil { collector.layouts.count == 1 }

        var renumbered = Self.left
        renumbered.cgDisplayID = 50
        fixture.screens.descriptors = [renumbered]
        fixture.postScreenChange()
        let delivered = await fixture.fireUntil { collector.layouts.count == 2 }

        #expect(delivered)
        #expect(collector.layouts[0].fingerprint == collector.layouts[1].fingerprint)
        #expect(collector.layouts[1].displays.first?.cgDisplayID == 50)
        collector.cancel()
    }

    @Test func streamsAreIndependent() async {
        let fixture = TrackerFixture([Self.left])
        let first = LayoutCollector(fixture.tracker.layouts())
        _ = await waitUntil { first.layouts.count == 1 }
        fixture.screens.descriptors = [Self.left, Self.right]
        fixture.postScreenChange()
        _ = await fixture.fireUntil { first.layouts.count == 2 }

        // A stream created later starts from the layout as it is now, not from the first stream's history.
        let second = LayoutCollector(fixture.tracker.layouts())
        _ = await waitUntil { second.layouts.count == 1 }
        #expect(second.layouts == [Self.twoDisplays])
        #expect(fixture.center.observerCount == 2)

        // Ending one stream leaves the other running.
        first.cancel()
        let removed = await waitUntil { fixture.center.observerCount == 1 }
        #expect(removed)
        #expect(first.layouts == [Self.oneDisplay, Self.twoDisplays])

        fixture.screens.descriptors = [Self.right]
        fixture.postScreenChange()
        let delivered = await fixture.fireUntil { second.layouts.count == 2 }

        #expect(delivered)
        #expect(second.layouts.last == ScreenDescriptor.layout(from: [Self.right]))
        #expect(first.layouts.count == 2)
        second.cancel()
    }

    @Test func eachStreamKeepsItsOwnLastYieldedValue() async {
        let fixture = TrackerFixture([Self.left])
        let first = LayoutCollector(fixture.tracker.layouts())
        _ = await waitUntil { first.layouts.count == 1 }
        fixture.screens.descriptors = [Self.left, Self.right]
        let second = LayoutCollector(fixture.tracker.layouts())
        _ = await waitUntil { second.layouts.count == 1 }

        fixture.postScreenChange()
        let delivered = await fixture.fireUntil { first.layouts.count == 2 }
        await settle()

        // The first stream sees the change. The second already yielded this layout, so it does not repeat it.
        #expect(delivered)
        #expect(first.layouts == [Self.oneDisplay, Self.twoDisplays])
        #expect(second.layouts == [Self.twoDisplays])
        first.cancel()
        second.cancel()
    }

    @Test func terminatingTheStreamRemovesTheObserverAndStopsRecomputing() async {
        let fixture = TrackerFixture([Self.left])
        let collector = LayoutCollector(fixture.tracker.layouts())
        _ = await waitUntil { collector.layouts.count == 1 }
        #expect(fixture.center.observerCount == 1)
        // Leave a debounce sleeping so cancellation has something to cancel.
        fixture.screens.descriptors = [Self.left, Self.right]
        fixture.postScreenChange()
        _ = await waitUntil { fixture.sleeper.pendingCount == 1 }

        collector.cancel()
        let removed = await waitUntil { fixture.center.observerCount == 0 }
        let finished = await waitUntil { collector.isFinished }
        let cancelled = await waitUntil { fixture.sleeper.pendingCount == 0 }

        #expect(removed)
        #expect(finished)
        #expect(cancelled)

        let startedBefore = fixture.sleeper.startedCount
        let readsBefore = fixture.screens.readCount
        fixture.postScreenChange()
        fixture.sleeper.fireAll()
        await settle()

        #expect(fixture.sleeper.startedCount == startedBefore)
        #expect(fixture.screens.readCount == readsBefore)
        #expect(collector.layouts == [Self.oneDisplay])
    }

    @Test func droppingAStreamWithoutConsumingItRemovesTheObserver() async {
        let fixture = TrackerFixture([Self.left])

        _ = fixture.tracker.layouts()
        let removed = await waitUntil { fixture.center.observerCount == 0 }

        #expect(removed)
    }

    @Test func realDebounceCoalescesABurstIntoOneRecompute() async {
        let fixture = TrackerFixture([Self.left], realDebounce: .milliseconds(30))
        let collector = LayoutCollector(fixture.tracker.layouts())
        _ = await waitUntil { collector.layouts.count == 1 }
        fixture.screens.descriptors = [Self.left, Self.right]

        for _ in 0..<3 {
            fixture.postScreenChange()
        }
        let delivered = await waitUntil { collector.layouts.count == 2 }
        // Wait past another debounce interval to catch any late extra recompute.
        try? await Task.sleep(for: .milliseconds(80))

        #expect(delivered)
        #expect(fixture.screens.readCount == 2)
        #expect(collector.layouts == [Self.oneDisplay, Self.twoDisplays])
        collector.cancel()
    }
}
