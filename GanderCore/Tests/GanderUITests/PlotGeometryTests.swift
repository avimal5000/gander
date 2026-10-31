import CoreGraphics
import GanderModels
import Testing

@testable import GanderUI

@Suite("Plot geometry")
struct PlotGeometryTests {
    @Test func ellipseIsClosedAndHasTheRequestedSemiAxes() throws {
        let points = PlotGeometry.ellipse(meanX: 10, meanY: -5, stdX: 2, stdY: 1, k: 2, segments: 48)
        #expect(points.count == 49)
        let first = try #require(points.first)
        let last = try #require(points.last)
        #expect(abs(first.x - last.x) < 1e-9)
        #expect(abs(first.y - last.y) < 1e-9)
        #expect(abs(points.map(\.x).max()! - 14) < 1e-9)
        #expect(abs(points.map(\.x).min()! - 6) < 1e-9)
        #expect(abs(points.map(\.y).max()! - -3) < 1e-6)
        #expect(abs(points.map(\.y).min()! - -7) < 1e-6)
    }

    @Test func ellipseWithZeroSpreadIsJustTheCenter() {
        let points = PlotGeometry.ellipse(meanX: 3, meanY: 4, stdX: 0, stdY: 0)
        #expect(points.count == 1)
        #expect(points[0].x == 3)
        #expect(points[0].y == 4)
    }

    @Test func domainPadsAndRoundsOutwardToTheStep() {
        let domain = PlotGeometry.domain(covering: [-40, 12], padding: 3, step: 5, minimumSpan: 30)
        #expect(domain.lowerBound == -45)
        #expect(domain.upperBound == 15)
    }

    @Test func domainNeverGetsNarrowerThanTheMinimumSpan() {
        let domain = PlotGeometry.domain(covering: [1, 2], padding: 1, step: 5, minimumSpan: 30)
        #expect(domain.upperBound - domain.lowerBound >= 30)
        #expect(domain.contains(1))
        #expect(domain.contains(2))
    }

    @Test func domainOfNoDataIsCenteredOnZero() {
        let domain = PlotGeometry.domain(covering: [])
        #expect(domain.lowerBound == -15)
        #expect(domain.upperBound == 15)
    }

    @Test func scatterPointsAreLabeledProjectedAndSkipUnusableSamples() {
        let labels = DisplayLabeler.labels(for: Fixtures.twoDisplays)
        let trace = PoseTrace(
            layout: Fixtures.twoDisplays,
            segments: [
                TraceSegment(
                    displayID: Fixtures.left.id, round: 1,
                    samples: [
                        PoseSample(
                            timestamp: 0, pose: Fixtures.pose(yaw: -20, pitch: 1, landmarkYaw: -18, landmarkPitch: 2)),
                        PoseSample(timestamp: 1, pose: nil),
                        PoseSample(timestamp: 2, pose: Fixtures.pose(yaw: -21, pitch: 0)),
                    ]),
                TraceSegment(displayID: nil, round: 0, samples: [Fixtures.sample(at: 3, yaw: 5)]),
                TraceSegment(
                    displayID: Fixtures.right.id, round: 1,
                    samples: [
                        PoseSample(
                            timestamp: 4, pose: Fixtures.pose(yaw: 20, pitch: -1, landmarkYaw: 17, landmarkPitch: -2))
                    ]),
            ]
        )

        let vision = PlotGeometry.scatterPoints(in: trace, featureSet: .visionAngles, labels: labels)
        #expect(vision.map(\.x) == [-20, -21, 20])
        #expect(vision.map(\.label) == ["Left", "Left", "Right"])
        #expect(Set(vision.map(\.id)).count == 3)

        let landmarks = PlotGeometry.scatterPoints(in: trace, featureSet: .landmarkAngles, labels: labels)
        #expect(landmarks.map(\.x) == [-18, 17])
        #expect(landmarks.map(\.y) == [2, -2])
    }

    @Test func clusterShapesFollowTheReportOrderAndUseUniqueLabels() {
        let report = Fixtures.report(.visionAngles, verdict: .go, offset: 20)
        let labels = [Fixtures.left.id: "Left (1)", Fixtures.right.id: "Left (2)"]
        let shapes = PlotGeometry.ClusterShape.shapes(for: report, labels: labels)
        #expect(shapes.map(\.label) == ["Left (1)", "Left (2)"])
        #expect(shapes.map(\.meanX) == [-20, 20])
        #expect(shapes.allSatisfy { $0.outline.count == 49 })
    }

    @Test func trailFadesWithAgeAndSkipsPosesWithoutTheFeatures() {
        let history = [
            PoseHistoryPoint(id: 0, timestamp: 0, pose: Fixtures.pose(yaw: -10, pitch: 1)),
            PoseHistoryPoint(
                id: 1, timestamp: 5, pose: Fixtures.pose(yaw: 0, pitch: 2, landmarkYaw: 3, landmarkPitch: 4)),
            PoseHistoryPoint(id: 2, timestamp: 10, pose: Fixtures.pose(yaw: 10, pitch: 3)),
        ]
        let vision = PlotTrail.points(history, featureSet: .visionAngles)
        #expect(vision.map(\.x) == [-10, 0, 10])
        #expect(vision.map(\.y) == [1, 2, 3])
        // Oldest (10 s) at 0.15, halfway at 0.575, newest at 1.
        #expect(vision.map(\.opacity).enumerated().allSatisfy { abs($0.element - [0.15, 0.575, 1][$0.offset]) < 1e-9 })

        let landmarks = PlotTrail.points(history, featureSet: .landmarkAngles)
        #expect(landmarks == [PlotTrail.Point(x: 3, y: 4, opacity: 0.575)])
        #expect(PlotTrail.points([], featureSet: .visionAngles).isEmpty)
    }
}
