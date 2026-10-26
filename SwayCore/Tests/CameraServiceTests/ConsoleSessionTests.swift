import CoreGraphics
import Testing

@testable import CameraService

@Suite("Console session check")
struct ConsoleSessionTests {
    private let key = kCGSessionOnConsoleKey as String

    @Test func aSessionOffTheConsoleIsInactive() {
        #expect(ConsoleSession.isInactive(sessionDictionary: [key: false]))
    }

    @Test func aSessionOnTheConsoleIsActive() {
        #expect(!ConsoleSession.isInactive(sessionDictionary: [key: true]))
    }

    @Test func noDictionaryMeansAssumeConsole() {
        #expect(!ConsoleSession.isInactive(sessionDictionary: nil))
    }

    @Test func aMissingOrMalformedKeyMeansAssumeConsole() {
        #expect(!ConsoleSession.isInactive(sessionDictionary: [:]))
        #expect(!ConsoleSession.isInactive(sessionDictionary: ["kCGSSessionUserNameKey": "someone"]))
        #expect(!ConsoleSession.isInactive(sessionDictionary: [key: "no"]))
    }
}
