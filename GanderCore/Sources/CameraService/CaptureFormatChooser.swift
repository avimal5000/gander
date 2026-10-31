import GanderModels

/// Pixel dimensions of a capture format.
struct VideoDimensions: Sendable, Equatable {
    var width: Int
    var height: Int

    var area: Int { width * height }
}

/// Pure format fallback (CONTRACT 6.1), used when the device does not support the 640x480 session preset.
enum CaptureFormatChooser {
    /// Index of the smallest format that is at least `GanderPolicy.captureWidth` (640) pixels wide, or `nil`
    /// when none is (the caller then keeps the device default).
    ///
    /// "Smallest" means the smallest pixel area; ties go to the earlier format. Only the width is checked,
    /// so a 16:9 format such as 640x360 qualifies.
    static func smallestSufficientIndex(among formats: [VideoDimensions]) -> Int? {
        var bestIndex: Int?
        for (index, format) in formats.enumerated() where format.width >= GanderPolicy.captureWidth {
            if let current = bestIndex, formats[current].area <= format.area { continue }
            bestIndex = index
        }
        return bestIndex
    }
}
