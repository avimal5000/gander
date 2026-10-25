import SwayModels

/// One labeled segment's samples, reduced to what the analysis needs.
struct LabeledSegment: Equatable {
    var round: Int
    var samples: [PoseSample]

    /// Feature points of the samples that have `featureSet` available, in time order.
    func points(for featureSet: PoseFeatureSet) -> [FeaturePoint] {
        samples.compactMap { sample in sample.pose.flatMap { featureSet.point(of: $0) } }
    }
}

/// All labeled segments of one display, in trace order.
struct LabeledDisplay: Equatable {
    var id: DisplayID
    var name: String
    var segments: [LabeledSegment]

    /// All frames in this display's labeled segments.
    var frameCount: Int {
        segments.reduce(0) { $0 + $1.samples.count }
    }

    /// Frames in which a face (any pose) was detected.
    var faceFrameCount: Int {
        segments.reduce(0) { total, segment in total + segment.samples.filter { $0.pose != nil }.count }
    }

    /// Feature points over all segments, in trace order.
    func points(for featureSet: PoseFeatureSet) -> [FeaturePoint] {
        segments.flatMap { $0.points(for: featureSet) }
    }

    /// Groups the labeled segments of `trace` by display, in order of first appearance. Unlabeled segments are
    /// ignored. Names come from the trace layout, falling back to the display ID's raw value.
    static func group(_ trace: PoseTrace) -> [LabeledDisplay] {
        var displays: [LabeledDisplay] = []
        var indexByID: [DisplayID: Int] = [:]
        for segment in trace.segments {
            guard let id = segment.displayID else { continue }
            let labeled = LabeledSegment(round: segment.round, samples: segment.samples)
            if let index = indexByID[id] {
                displays[index].segments.append(labeled)
            } else {
                indexByID[id] = displays.count
                let name = trace.layout?.display(withID: id)?.name ?? id.rawValue
                displays.append(LabeledDisplay(id: id, name: name, segments: [labeled]))
            }
        }
        return displays
    }
}
