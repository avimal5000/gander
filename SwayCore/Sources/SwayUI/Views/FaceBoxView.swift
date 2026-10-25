import SwiftUI

/// A schematic of where the face sits in the camera frame (SPEC D9: no video, just a box).
struct FaceBoxView: View {
    /// Face box in Vision's normalized coordinates (origin bottom-left); `nil` when no face was found.
    let faceBounds: CGRect?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Canvas { context, size in
                let frame = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
                context.stroke(Path(roundedRect: frame, cornerRadius: 8), with: .color(.secondary), lineWidth: 1)

                var cross = Path()
                cross.move(to: CGPoint(x: frame.midX, y: frame.minY))
                cross.addLine(to: CGPoint(x: frame.midX, y: frame.maxY))
                cross.move(to: CGPoint(x: frame.minX, y: frame.midY))
                cross.addLine(to: CGPoint(x: frame.maxX, y: frame.midY))
                context.stroke(
                    cross, with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))

                if let faceBounds {
                    let rect = Self.viewRect(for: faceBounds, in: frame)
                    let accent = SwayPalette.accent(for: colorScheme)
                    context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(accent.opacity(0.18)))
                    context.stroke(Path(roundedRect: rect, cornerRadius: 6), with: .color(accent), lineWidth: 2)
                }
            }
            if faceBounds == nil {
                Text("No face")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(faceBounds == nil ? "Camera frame: no face" : "Camera frame: face detected")
    }

    /// Converts a Vision box (origin bottom-left) into a rectangle inside `frame` (origin top-left).
    nonisolated static func viewRect(for bounds: CGRect, in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + bounds.minX * frame.width,
            y: frame.minY + (1 - bounds.maxY) * frame.height,
            width: bounds.width * frame.width,
            height: bounds.height * frame.height
        )
    }
}
