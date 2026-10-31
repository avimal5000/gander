import ApplicationServices
import CoreGraphics
import Foundation

/// Thin typed wrappers over the Accessibility attribute API. All calls block, so call them only from the
/// controller's serial queue. Window titles are returned to the caller and never logged here.
enum AXElementAccess {
    /// A raw attribute read: the value, or the `AXError` explaining its absence.
    struct Reading {
        let value: CFTypeRef?
        let error: AXError

        /// True when the app did not answer within the messaging timeout.
        var timedOut: Bool { error == .cannotComplete }
    }

    /// A frame read: the frame when both position and size could be read, and whether the app timed out.
    struct FrameReading {
        let frame: CGRect?
        let timedOut: Bool
    }

    static func read(_ attribute: String, of element: AXUIElement) -> Reading {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return Reading(value: error == .success ? value : nil, error: error)
    }

    /// The app's windows, front to back as the app reports them. `nil` when unreadable.
    static func windows(of app: AXUIElement) -> [AXUIElement]? {
        read(kAXWindowsAttribute, of: app).value as? [AXUIElement]
    }

    /// The app's focused window, or `nil` when it has none or it cannot be read.
    static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        guard let value = read(kAXFocusedWindowAttribute, of: app).value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    /// The window's frame in Quartz global coordinates, from its position and size attributes.
    static func frame(of window: AXUIElement) -> FrameReading {
        let positionReading = read(kAXPositionAttribute, of: window)
        if positionReading.timedOut { return FrameReading(frame: nil, timedOut: true) }
        let sizeReading = read(kAXSizeAttribute, of: window)
        if sizeReading.timedOut { return FrameReading(frame: nil, timedOut: true) }
        guard let origin = cgPoint(from: positionReading.value), let extent = cgSize(from: sizeReading.value) else {
            return FrameReading(frame: nil, timedOut: false)
        }
        return FrameReading(frame: CGRect(origin: origin, size: extent), timedOut: false)
    }

    /// The window's title, or `nil` if it has none.
    static func title(of window: AXUIElement) -> String? {
        read(kAXTitleAttribute, of: window).value as? String
    }

    /// Performs the raise action on `window`.
    @discardableResult
    static func raise(_ window: AXUIElement) -> AXError {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    /// Sets a boolean attribute to true.
    @discardableResult
    static func setTrue(_ attribute: String, on element: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, kCFBooleanTrue)
    }

    private static func cgPoint(from value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var point = CGPoint.zero
        guard AXValueGetType(axValue) == .cgPoint, AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func cgSize(from value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var size = CGSize.zero
        guard AXValueGetType(axValue) == .cgSize, AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}
