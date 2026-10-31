// See CarbonHotKeyMapping.swift: Carbon has no Sendable annotations.
@preconcurrency import Carbon
import Foundation
import SwayModels
import os

/// Owns every live Carbon handle: the registered hot keys, their handlers, and the single application event handler.
///
/// Carbon calls back through a C function pointer that can't capture anything, so this object is the context: its
/// address travels as the event handler's `userData`. It is deliberately not main-actor isolated, so the center's
/// nonisolated `deinit` can release the handles.
///
/// `@unchecked Sendable`: all mutable state lives in `state`, and `state` is only reached through its lock.
final class CarbonHotKeyRegistry: @unchecked Sendable {
    private struct Entry {
        let reference: EventHotKeyRef
        let handler: @MainActor () -> Void
    }

    private struct State {
        var entries: [HotKeyAction: Entry] = [:]
        var eventHandler: EventHandlerRef?
    }

    /// Carbon's opaque references aren't `Sendable`, so the unchecked variant is needed; the lock still serializes
    /// every access.
    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    /// Registers `keyCode` plus `modifiers` (Carbon flags) for `action`, replacing the action's previous hot key.
    /// Returns `noErr` on success. On any failure the action has no hot key, and when nothing else is registered the
    /// event handler is removed again.
    func register(
        keyCode: UInt32, modifiers: UInt32, action: HotKeyAction, handler: @escaping @MainActor () -> Void
    ) -> OSStatus {
        state.withLockUnchecked { state in
            removeHotKey(for: action, in: &state)

            var reference: EventHotKeyRef?
            let registerStatus = RegisterEventHotKey(
                keyCode, modifiers, CarbonHotKeyMapping.hotKeyID(for: action), GetApplicationEventTarget(), 0,
                &reference)
            guard registerStatus == OSStatus(noErr), let reference else {
                removeEventHandlerIfIdle(in: &state)
                // Carbon reporting success without a reference would be a bug; never claim success then.
                return registerStatus == OSStatus(noErr) ? OSStatus(paramErr) : registerStatus
            }

            let installStatus = installEventHandlerIfNeeded(in: &state)
            guard installStatus == OSStatus(noErr) else {
                UnregisterEventHotKey(reference)
                return installStatus
            }
            state.entries[action] = Entry(reference: reference, handler: handler)
            return OSStatus(noErr)
        }
    }

    /// Removes the hot key for `action`. Returns whether it had one. Removes the event handler with the last hot key.
    @discardableResult
    func unregister(_ action: HotKeyAction) -> Bool {
        state.withLockUnchecked { state in
            let hadHotKey = removeHotKey(for: action, in: &state)
            removeEventHandlerIfIdle(in: &state)
            return hadHotKey
        }
    }

    /// Removes every hot key and the event handler.
    func unregisterAll() {
        state.withLockUnchecked { state in
            for action in Array(state.entries.keys) {
                removeHotKey(for: action, in: &state)
            }
            removeEventHandlerIfIdle(in: &state)
        }
    }

    /// The handler registered for `hotKeyID`, or nil when it isn't one of Gander's live hot keys.
    func handler(for hotKeyID: EventHotKeyID) -> (@MainActor () -> Void)? {
        guard let action = CarbonHotKeyMapping.action(for: hotKeyID) else { return nil }
        return state.withLockUnchecked { $0.entries[action]?.handler }
    }

    // MARK: - Locked helpers (call only from inside `state.withLockUnchecked`)

    @discardableResult
    private func removeHotKey(for action: HotKeyAction, in state: inout State) -> Bool {
        guard let entry = state.entries.removeValue(forKey: action) else { return false }
        UnregisterEventHotKey(entry.reference)
        return true
    }

    private func installEventHandlerIfNeeded(in state: inout State) -> OSStatus {
        guard state.eventHandler == nil else { return OSStatus(noErr) }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var reference: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in CarbonHotKeyRegistry.handleHotKeyEvent(event, userData: userData) },
            1,
            &eventType,
            // Unretained: the center owns this object and calls `unregisterAll()` (which removes the handler) in
            // its deinit, so the handler never outlives it.
            Unmanaged.passUnretained(self).toOpaque(),
            &reference)
        if status == OSStatus(noErr) { state.eventHandler = reference }
        return status
    }

    private func removeEventHandlerIfIdle(in state: inout State) {
        guard state.entries.isEmpty, let eventHandler = state.eventHandler else { return }
        RemoveEventHandler(eventHandler)
        state.eventHandler = nil
    }

    // MARK: - Event delivery

    /// Runs on Carbon's callback, which fires on the main thread. Reads which hot key was pressed and runs its
    /// handler outside the lock, so a handler may register or unregister shortcuts itself.
    private static func handleHotKeyEvent(_ event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
            MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        guard status == OSStatus(noErr) else { return status }

        let registry = Unmanaged<CarbonHotKeyRegistry>.fromOpaque(userData).takeUnretainedValue()
        guard let handler = registry.handler(for: hotKeyID) else { return OSStatus(eventNotHandledErr) }
        MainActor.assumeIsolated { handler() }
        return OSStatus(noErr)
    }
}
