@preconcurrency import Carbon
import SwayModels
import Testing

@testable import SystemIntegration

@Suite struct CarbonHotKeyMappingTests {
    // MARK: - Modifiers

    @Test(arguments: [
        (HotKeyShortcut.Modifiers.control, controlKey),
        (.option, optionKey),
        (.shift, shiftKey),
        (.command, cmdKey),
    ])
    func mapsEachModifierToItsCarbonFlag(modifier: HotKeyShortcut.Modifiers, carbonFlag: Int) {
        #expect(CarbonHotKeyMapping.carbonModifiers(for: modifier) == UInt32(carbonFlag))
    }

    @Test func carbonFlagsHaveTheDocumentedBitValues() {
        #expect(CarbonHotKeyMapping.carbonModifiers(for: .command) == 0x0100)
        #expect(CarbonHotKeyMapping.carbonModifiers(for: .shift) == 0x0200)
        #expect(CarbonHotKeyMapping.carbonModifiers(for: .option) == 0x0800)
        #expect(CarbonHotKeyMapping.carbonModifiers(for: .control) == 0x1000)
    }

    @Test func combinesModifierFlags() {
        let all: HotKeyShortcut.Modifiers = [.control, .option, .shift, .command]
        #expect(CarbonHotKeyMapping.carbonModifiers(for: all) == 0x1000 | 0x0800 | 0x0200 | 0x0100)
        #expect(
            CarbonHotKeyMapping.carbonModifiers(for: HotKeyShortcut.focusLockDefault.modifiers)
                == UInt32(controlKey | optionKey | cmdKey))
    }

    @Test func noModifiersMapToNoFlags() {
        #expect(CarbonHotKeyMapping.carbonModifiers(for: []) == 0)
    }

    // MARK: - Signature

    @Test func signatureIsSWAY() {
        #expect(CarbonHotKeyMapping.signatureText == "SWAY")
        #expect(CarbonHotKeyMapping.signature == 0x5357_4159)
    }

    @Test func fourCharCodeIsBigEndianAndRoundTrips() {
        let code = CarbonHotKeyMapping.fourCharCode("SWAY")
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        #expect(String(decoding: bytes, as: UTF8.self) == "SWAY")
        #expect(CarbonHotKeyMapping.fourCharCode("abcd") == 0x6162_6364)
    }

    @Test func fourCharCodeIgnoresCharactersBeyondTheFourth() {
        #expect(CarbonHotKeyMapping.fourCharCode("SWAYZ") == CarbonHotKeyMapping.signature)
    }

    // MARK: - Action and hot key ID

    @Test func toggleFocusLockKeepsItsFirstID() {
        #expect(CarbonHotKeyMapping.actionID(for: .toggleFocusLock) == 1)
    }

    @Test func actionIDsAreDistinctAndOneBased() {
        let ids = HotKeyAction.allCases.map(CarbonHotKeyMapping.actionID(for:))
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0 >= 1 })
    }

    @Test(arguments: HotKeyAction.allCases)
    func hotKeyIDRoundTripsToItsAction(action: HotKeyAction) {
        let hotKeyID = CarbonHotKeyMapping.hotKeyID(for: action)
        #expect(hotKeyID.signature == CarbonHotKeyMapping.signature)
        #expect(hotKeyID.id == CarbonHotKeyMapping.actionID(for: action))
        #expect(CarbonHotKeyMapping.action(for: hotKeyID) == action)
    }

    @Test func ignoresHotKeysWithAnotherSignature() {
        let foreign = EventHotKeyID(signature: CarbonHotKeyMapping.fourCharCode("OTHR"), id: 1)
        #expect(CarbonHotKeyMapping.action(for: foreign) == nil)
    }

    @Test(arguments: [0, 2, 99, UInt32.max] as [UInt32])
    func ignoresUnknownActionIDs(id: UInt32) {
        #expect(CarbonHotKeyMapping.action(for: EventHotKeyID(signature: CarbonHotKeyMapping.signature, id: id)) == nil)
    }

    // MARK: - Status mapping

    @Test func successIsNotAnError() {
        #expect(CarbonHotKeyMapping.error(forStatus: OSStatus(noErr)) == nil)
    }

    @Test func existingHotKeyMeansShortcutInUse() {
        #expect(CarbonHotKeyMapping.error(forStatus: OSStatus(eventHotKeyExistsErr)) == .shortcutInUse)
        #expect(OSStatus(eventHotKeyExistsErr) == -9878)
    }

    @Test(arguments: [OSStatus(eventHotKeyInvalidErr), OSStatus(paramErr), OSStatus(eventNotHandledErr), -1, 1])
    func otherStatusesCarryTheirCode(status: OSStatus) {
        #expect(CarbonHotKeyMapping.error(forStatus: status) == .registrationFailed(status))
    }
}
