import AppKit
import GanderModels
import Testing

@testable import GanderUI

@Suite("Shortcut mapping")
struct ShortcutMappingTests {
    private let all: NSEvent.ModifierFlags = [.control, .option, .command]

    private func capture(
        _ keyCode: UInt16, _ flags: NSEvent.ModifierFlags, _ characters: String? = nil
    ) -> ShortcutCapture {
        ShortcutMapping.capture(
            ShortcutKeyPress(keyCode: keyCode, modifierFlags: flags, charactersIgnoringModifiers: characters))
    }

    // MARK: Keys

    @Test func lettersBecomeUppercaseLabels() {
        #expect(
            capture(37, all, "l")
                == .shortcut(HotKeyShortcut(keyCode: 37, modifiers: [.control, .option, .command], keyLabel: "L")))
        #expect(capture(37, all, "l") == .shortcut(.focusLockDefault))
        #expect(
            capture(0, [.command], "a") == .shortcut(HotKeyShortcut(keyCode: 0, modifiers: [.command], keyLabel: "A")))
    }

    @Test func digitsAndPunctuationUseTheirCharacter() {
        #expect(
            capture(18, [.control], "1") == .shortcut(HotKeyShortcut(keyCode: 18, modifiers: [.control], keyLabel: "1"))
        )
        #expect(
            capture(44, [.command], "/") == .shortcut(HotKeyShortcut(keyCode: 44, modifiers: [.command], keyLabel: "/"))
        )
    }

    @Test func namedKeysUseTheirNames() {
        let names: [UInt16: String] = [
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Escape",
            123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}",
        ]
        for (code, name) in names {
            #expect(ShortcutMapping.keyLabel(keyCode: code, characters: nil) == name, "\(code)")
            #expect(
                capture(code, [.command], "x")
                    == .shortcut(HotKeyShortcut(keyCode: code, modifiers: [.command], keyLabel: name)))
        }
    }

    @Test func aNamedKeyIgnoresTheCharacterTheEventReports() {
        // AppKit reports private-use characters for function and arrow keys.
        #expect(ShortcutMapping.keyLabel(keyCode: 126, characters: "\u{F700}") == "\u{2191}")
        #expect(ShortcutMapping.keyLabel(keyCode: 122, characters: "\u{F704}") == "F1")
    }

    @Test func functionKeysOneToTwentyHaveNames() {
        let codes: [UInt16] = [
            122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
        ]
        #expect(codes.count == 20)
        for (index, code) in codes.enumerated() {
            #expect(ShortcutMapping.keyLabel(keyCode: code, characters: nil) == "F\(index + 1)")
        }
        #expect(Set(codes).count == 20, "Every F-key has its own key code")
    }

    @Test func otherNavigationKeysHaveNames() {
        #expect(ShortcutMapping.keyLabel(keyCode: 115, characters: nil) == "Home")
        #expect(ShortcutMapping.keyLabel(keyCode: 119, characters: nil) == "End")
        #expect(ShortcutMapping.keyLabel(keyCode: 116, characters: nil) == "Page Up")
        #expect(ShortcutMapping.keyLabel(keyCode: 121, characters: nil) == "Page Down")
        #expect(ShortcutMapping.keyLabel(keyCode: 117, characters: nil) == "Forward Delete")
        #expect(ShortcutMapping.keyLabel(keyCode: 76, characters: nil) == "Enter")
    }

    @Test func aKeyWithNeitherANameNorACharacterHasNoLabel() {
        #expect(ShortcutMapping.keyLabel(keyCode: 200, characters: nil) == nil)
        #expect(ShortcutMapping.keyLabel(keyCode: 200, characters: "") == nil)
        #expect(ShortcutMapping.keyLabel(keyCode: 200, characters: "ab") == nil)
        #expect(ShortcutMapping.keyLabel(keyCode: 200, characters: "\u{1B}") == nil, "A control character")
        #expect(ShortcutMapping.keyLabel(keyCode: 200, characters: "\u{F72B}") == nil, "A private-use function key")
        #expect(ShortcutMapping.keyLabel(keyCode: 200, characters: " ") == nil, "Space has its own name")
    }

    // MARK: Modifiers

    @Test func eachModifierMapsAlone() {
        #expect(ShortcutMapping.modifiers(from: [.control]) == [.control])
        #expect(ShortcutMapping.modifiers(from: [.option]) == [.option])
        #expect(ShortcutMapping.modifiers(from: [.shift]) == [.shift])
        #expect(ShortcutMapping.modifiers(from: [.command]) == [.command])
        #expect(ShortcutMapping.modifiers(from: []) == [])
    }

    @Test func modifiersCombineAndOtherFlagsAreIgnored() {
        #expect(ShortcutMapping.modifiers(from: [.control, .option, .command]) == [.control, .option, .command])
        #expect(ShortcutMapping.modifiers(from: [.shift, .command, .capsLock, .function]) == [.shift, .command])
    }

    @Test func aShiftedShortcutKeepsShiftInItsDisplay() {
        let result = capture(37, [.command, .shift], "L")
        #expect(result == .shortcut(HotKeyShortcut(keyCode: 37, modifiers: [.command, .shift], keyLabel: "L")))
        if case .shortcut(let shortcut) = result { #expect(shortcut.displayString == "\u{21E7}\u{2318}L") }
    }

    // MARK: Invalid and cancelling

    @Test func aKeyWithoutControlOptionOrCommandIsInvalid() {
        #expect(capture(37, [], "l") == .invalid)
        #expect(capture(37, [.shift], "L") == .invalid)
        #expect(capture(49, [], nil) == .invalid)
        #expect(capture(122, [.shift], nil) == .invalid)
        #expect(ShortcutMapping.invalidMessage == "Use Control, Option, or Command with a key.")
    }

    @Test func aModifierComboWithoutAnyKeyLabelIsInvalid() {
        #expect(capture(200, all, nil) == .invalid)
    }

    @Test func escapeOnItsOwnCancels() {
        #expect(capture(53, [], nil) == .cancel)
        #expect(capture(53, [.shift], nil) == .cancel)
    }

    @Test func escapeWithAnActionModifierIsAShortcutLikeAnyOtherKey() {
        #expect(
            capture(53, [.command], nil)
                == .shortcut(HotKeyShortcut(keyCode: 53, modifiers: [.command], keyLabel: "Escape")))
    }

    @Test func everyShortcutTheMappingProducesIsValid() {
        for result in [capture(37, all, "l"), capture(49, [.option], nil), capture(122, [.control, .shift], nil)] {
            guard case .shortcut(let shortcut) = result else {
                Issue.record("Expected a shortcut, got \(result)")
                continue
            }
            #expect(shortcut.isValid)
        }
    }
}
