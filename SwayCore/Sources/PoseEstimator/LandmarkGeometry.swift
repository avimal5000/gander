import CoreGraphics
import Foundation

/// Pure geometry that turns a handful of face landmarks into a yaw/pitch proxy (SPEC D10).
///
/// Vision's own yaw and pitch can be coarse. This proxy is computed from the *positions* of the eyes and the
/// nose tip, so it is continuous, needs no model, and can be unit tested over plain `CGPoint` inputs.
///
/// ## Coordinates
/// All inputs are landmark points normalized to the face bounding box (Vision's
/// `VNFaceLandmarkRegion2D.normalizedPoints`: `0...1` inside the box, origin bottom-left, y up). The box is
/// normalized by the *image* size, so it is only roughly square in pixels. `boxAspect` is the box's pixel
/// width divided by its pixel height; x is multiplied by it so that distances are isotropic ("box-height units").
///
/// ## Reference points
/// - **Eye center** of each eye: the centroid of the eye-region outline (Vision's `leftEye` / `rightEye`), never
///   the pupil. Pupils move with gaze, and PLAN.md defers eye gaze, so a pupil-based center would let eye movement
///   leak into the head-pose proxy. The two eyes are ordered by x, so it does not matter which one Vision calls
///   "left".
/// - **Nose tip**: the average of the centroid of the `nose` outline and the `noseCrest` point farthest from
///   the eye midpoint (the crest's end is the tip, whichever way Vision orders its points). If only one of the
///   two regions exists, that one is used alone.
///
/// ## Frame
/// Let `L` and `R` be the eye centers (left to right in the image), `io = |R - L|` the inter-ocular distance,
/// `u = (R - L) / io` the unit vector along the eye line, `v` the unit vector 90 degrees counterclockwise from
/// `u` (up in the face), and `d = nose - (L + R) / 2`. Measuring along the eye line instead of the image axes
/// makes the result independent of in-plane head roll.
///
/// - `h = (d . u) / io`, the sideways offset of the nose from the eye midpoint, in inter-ocular distances.
/// - `w = (d . v) / io`, the vertical offset (negative when the nose is below the eye line).
///
/// ## Head model
/// The nose tip sits `B = 0.45` inter-ocular distances in front of the eye line (`noseProtrusion`) and
/// `A = 0.6` below it (`noseDrop`); both are approximate anthropometric ratios from generic head models,
/// to be tuned with hardware data. The head is pitched first, then yawed. With `phi` the head tilted up and
/// `theta` the yaw, and `IPD` the true (frontal) inter-ocular distance:
///
/// - Pitch moves the nose to a height `w = -A cos(phi) + B sin(phi)` relative to the eye line and a depth
///   `z = A sin(phi) + B cos(phi)` in front of it, so `w^2 + z^2 = R^2` with `R = hypot(A, B)` for every pitch.
/// - Yaw shifts the nose sideways by `z sin(theta)` and shrinks the eye line to `IPD cos(theta)`.
///
/// What the image shows is therefore `h = z tan(theta)` and `v = w / cos(theta)` (both in units of the
/// projected inter-ocular distance). Eliminating `phi` with `w^2 + z^2 = R^2` gives a quadratic in
/// `s = sin^2(theta)`:
///
///     v^2 s^2 + (R^2 + h^2 - v^2) s - h^2 = 0
///
/// whose root in `(0, 1)` is `s = 2 h^2 / (b + sqrt(b^2 + 4 v^2 h^2))` with `b = R^2 + h^2 - v^2`. Then
/// `theta = sign(h) asin(sqrt(s))`, `w = v cos(theta)`, and `phi = phi0 + asin(w / R)` with `phi0 = atan2(A, B)`.
/// This inverts the model exactly, so yaw and pitch do not leak into each other. `asin` becomes steep as
/// `|w / R|` approaches 1 (the nose at its farthest drop), so beyond `|w / R| = 0.9` it continues along its
/// tangent line (`extendedArcsine`): strictly monotonic and finite where a real face, whose nose is longer
/// or lower than the model's, would otherwise hit a cliff, and with the noise gain capped at about 2.3.
/// The inversion is therefore exact down to a nod of about 11 degrees below neutral and approximate beyond.
///
/// ## Result (degree-equivalents)
/// - `yaw = degrees(theta)`. Positive when the nose is displaced toward image-right in the unmirrored frame,
///   which is the head turning to the person's left, the direction of Vision's positive yaw
///   ("counterclockwise", seen from above).
/// - `pitch = -degrees(phi)`. Positive when nodding down, matching Vision's pitch sign. It is exactly `0` for a
///   nose at `v = -A`, the neutral ratio.
///
/// Both are continuous and strictly monotonic (`yaw` in `h`, `pitch` in `v`), and `0` for a face looking
/// straight at the camera that matches the neutral ratios. A person whose real ratios differ gets a constant
/// offset (the camera usually also sits above the screen); the M1 gate needs the proxy to separate displays,
/// not to be absolute.
enum LandmarkGeometry {
    /// Landmark inputs in face-box-normalized coordinates. An empty array means "region not found".
    ///
    /// There are deliberately no pupil inputs: eye centers come from the eye-region outlines only (see above).
    struct Points: Equatable, Sendable {
        var leftEyeRegion: [CGPoint]
        var rightEyeRegion: [CGPoint]
        var noseRegion: [CGPoint]
        var noseCrestRegion: [CGPoint]

        init(
            leftEyeRegion: [CGPoint] = [],
            rightEyeRegion: [CGPoint] = [],
            noseRegion: [CGPoint] = [],
            noseCrestRegion: [CGPoint] = []
        ) {
            self.leftEyeRegion = leftEyeRegion
            self.rightEyeRegion = rightEyeRegion
            self.noseRegion = noseRegion
            self.noseCrestRegion = noseCrestRegion
        }
    }

    /// The landmark-derived angle proxies, degree-equivalents.
    struct Angles: Equatable, Sendable {
        var yaw: Double
        var pitch: Double
    }

    /// Nose-tip protrusion in front of the eye line, in inter-ocular distances (`B` in the model).
    static let noseProtrusion = 0.45
    /// Nose-tip drop below the eye line when facing the camera, in inter-ocular distances (`A`, the neutral ratio).
    static let noseDrop = 0.6
    /// Smallest usable inter-ocular distance in box-height units; below this the eyes are degenerate.
    static let minimumInterocularDistance = 1e-4

    /// Computes the yaw/pitch proxy, or `nil` when either an eye or the nose is missing or the geometry is
    /// degenerate (non-finite points, eyes on top of each other).
    ///
    /// - Parameters:
    ///   - points: landmark points normalized to the face box.
    ///   - boxAspect: face box pixel width divided by pixel height; `1` if unknown.
    static func angles(from points: Points, boxAspect: Double = 1) -> Angles? {
        guard boxAspect.isFinite, boxAspect > 0 else { return nil }
        func isotropic(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * boxAspect, y: point.y) }

        guard
            let firstEye = eyeCenter(region: points.leftEyeRegion),
            let secondEye = eyeCenter(region: points.rightEyeRegion)
        else { return nil }
        let first = isotropic(firstEye)
        let second = isotropic(secondEye)
        let midpoint = CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)

        guard
            let nose = noseTip(
                noseRegion: points.noseRegion.map(isotropic),
                noseCrestRegion: points.noseCrestRegion.map(isotropic),
                eyeMidpoint: midpoint
            )
        else { return nil }
        return angles(firstEye: first, secondEye: second, noseTip: nose)
    }

    /// The center of one eye: the centroid of the finite points of its eye-region outline, or `nil` when there are
    /// none. Never the pupil (CONTRACT 6.2).
    static func eyeCenter(region: [CGPoint]) -> CGPoint? {
        centroid(of: region)
    }

    /// The nose tip: the mean of the `nose` outline centroid and the `noseCrest` point farthest from
    /// `eyeMidpoint`; whichever exists if only one does; `nil` if neither does.
    static func noseTip(noseRegion: [CGPoint], noseCrestRegion: [CGPoint], eyeMidpoint: CGPoint) -> CGPoint? {
        let outlineCentroid = centroid(of: noseRegion)
        let crestTip = noseCrestRegion.filter(isFinite).max { lhs, rhs in
            distanceSquared(lhs, eyeMidpoint) < distanceSquared(rhs, eyeMidpoint)
        }
        switch (outlineCentroid, crestTip) {
        case let (outline?, crest?):
            return CGPoint(x: (outline.x + crest.x) / 2, y: (outline.y + crest.y) / 2)
        case let (outline?, nil):
            return outline
        case let (nil, crest?):
            return crest
        case (nil, nil):
            return nil
        }
    }

    /// The core formula over three isotropic points (see the type documentation). The eyes may be given in
    /// either order.
    static func angles(firstEye: CGPoint, secondEye: CGPoint, noseTip: CGPoint) -> Angles? {
        guard isFinite(firstEye), isFinite(secondEye), isFinite(noseTip) else { return nil }
        let (left, right) = firstEye.x <= secondEye.x ? (firstEye, secondEye) : (secondEye, firstEye)
        let eyeX = right.x - left.x
        let eyeY = right.y - left.y
        let io = hypot(eyeX, eyeY)
        guard io > minimumInterocularDistance else { return nil }

        // Unit vectors along the eye line (u) and 90 degrees counterclockwise from it (v).
        let ux = eyeX / io
        let uy = eyeY / io
        let dx = noseTip.x - (left.x + right.x) / 2
        let dy = noseTip.y - (left.y + right.y) / 2
        let horizontal = (dx * ux + dy * uy) / io
        let vertical = (-dx * uy + dy * ux) / io

        // Solve the head model for the yaw (see the type documentation).
        let radius = hypot(noseDrop, noseProtrusion)
        let hSquared = horizontal * horizontal
        let vSquared = vertical * vertical
        var sinSquared = 0.0
        if hSquared > 1e-18 {
            let b = radius * radius + hSquared - vSquared
            let root = (b * b + 4 * vSquared * hSquared).squareRoot()
            // Both forms are the same root; each avoids cancellation for its own sign of b.
            sinSquared = b >= 0 ? 2 * hSquared / (b + root) : (root - b) / (2 * vSquared)
        }
        guard sinSquared.isFinite else { return nil }
        sinSquared = min(sinSquared, 1)
        let yaw = horizontal < 0 ? -asin(sinSquared.squareRoot()) : asin(sinSquared.squareRoot())

        // Undo the foreshortening of the eye line, then read the pitch off the nose height.
        let noseHeight = vertical * (1 - sinSquared).squareRoot()
        let tiltUp = atan2(noseDrop, noseProtrusion) + extendedArcsine(noseHeight / radius)

        return Angles(yaw: yaw * 180 / .pi, pitch: -tiltUp * 180 / .pi)
    }

    /// `asin(x)` up to `|x| = 0.9`, then its tangent line at that point, so it stays strictly increasing and
    /// finite instead of leaving its domain. Inputs beyond `|x| = 2` are clamped (nonsense geometry).
    static func extendedArcsine(_ x: Double) -> Double {
        let limit = 0.9
        let magnitude = min(abs(x), 2)
        let value: Double
        if magnitude <= limit {
            value = asin(magnitude)
        } else {
            let slope = 1 / (1 - limit * limit).squareRoot()
            value = asin(limit) + slope * (magnitude - limit)
        }
        return x < 0 ? -value : value
    }

    private static func centroid(of points: [CGPoint]) -> CGPoint? {
        let valid = points.filter(isFinite)
        guard !valid.isEmpty else { return nil }
        let count = Double(valid.count)
        return CGPoint(x: valid.reduce(0) { $0 + $1.x } / count, y: valid.reduce(0) { $0 + $1.y } / count)
    }

    private static func isFinite(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
    }

    private static func distanceSquared(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }
}
