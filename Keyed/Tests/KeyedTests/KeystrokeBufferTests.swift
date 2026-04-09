import XCTest
@testable import Keyed

final class KeystrokeBufferTests: XCTestCase {

    // MARK: - Basic appending

    func test_append_singleCharacter_bufferContainsIt() {
        var buffer = KeystrokeBuffer(capacity: 64)
        buffer.append("a")
        XCTAssertEqual(buffer.contents, "a")
    }

    func test_append_multipleCharacters_bufferContainsAll() {
        var buffer = KeystrokeBuffer(capacity: 64)
        buffer.append("h")
        buffer.append("i")
        XCTAssertEqual(buffer.contents, "hi")
    }

    // MARK: - Ring buffer overflow

    func test_append_exceedsCapacity_dropsOldestCharacters() {
        var buffer = KeystrokeBuffer(capacity: 4)
        for char in "abcde" {
            buffer.append(String(char))
        }
        XCTAssertEqual(buffer.contents, "bcde")
    }

    func test_append_exactlyAtCapacity_retainsAll() {
        var buffer = KeystrokeBuffer(capacity: 4)
        for char in "abcd" {
            buffer.append(String(char))
        }
        XCTAssertEqual(buffer.contents, "abcd")
    }

    // MARK: - Match detection

    func test_matchesAbbreviation_exactMatch_returnsTrue() {
        var buffer = KeystrokeBuffer(capacity: 64)
        for char in ":email" {
            buffer.append(String(char))
        }
        XCTAssertTrue(buffer.hasSuffix(":email"))
    }

    func test_matchesAbbreviation_partialMatch_returnsFalse() {
        var buffer = KeystrokeBuffer(capacity: 64)
        for char in ":ema" {
            buffer.append(String(char))
        }
        XCTAssertFalse(buffer.hasSuffix(":email"))
    }

    func test_matchesAbbreviation_matchAtEndOfLongerBuffer_returnsTrue() {
        var buffer = KeystrokeBuffer(capacity: 64)
        for char in "hello :sig" {
            buffer.append(String(char))
        }
        XCTAssertTrue(buffer.hasSuffix(":sig"))
    }

    func test_matchesAbbreviation_abbreviationLongerThanBuffer_returnsFalse() {
        var buffer = KeystrokeBuffer(capacity: 4)
        for char in "ab" {
            buffer.append(String(char))
        }
        XCTAssertFalse(buffer.hasSuffix("abcdef"))
    }

    func test_matchesAbbreviation_emptyBuffer_returnsFalse() {
        let buffer = KeystrokeBuffer(capacity: 64)
        XCTAssertFalse(buffer.hasSuffix(":email"))
    }

    // MARK: - First match from dictionary

    func test_firstMatch_findsMatchingAbbreviation() {
        var buffer = KeystrokeBuffer(capacity: 64)
        for char in ":email" {
            buffer.append(String(char))
        }
        let abbreviations: Set<String> = [":email", ":sig", ":addr"]
        XCTAssertEqual(buffer.firstMatch(from: abbreviations), ":email")
    }

    func test_firstMatch_noMatch_returnsNil() {
        var buffer = KeystrokeBuffer(capacity: 64)
        for char in ":em" {
            buffer.append(String(char))
        }
        let abbreviations: Set<String> = [":email", ":sig"]
        XCTAssertNil(buffer.firstMatch(from: abbreviations))
    }

    // MARK: - Reset

    func test_reset_clearsBuffer() {
        var buffer = KeystrokeBuffer(capacity: 64)
        for char in "hello" {
            buffer.append(String(char))
        }
        buffer.reset()
        XCTAssertEqual(buffer.contents, "")
        XCTAssertFalse(buffer.hasSuffix("hello"))
    }

    // MARK: - Backspace handling

    func test_backspace_removesLastCharacter() {
        var buffer = KeystrokeBuffer(capacity: 64)
        for char in "hello" {
            buffer.append(String(char))
        }
        buffer.backspace()
        XCTAssertEqual(buffer.contents, "hell")
    }

    func test_backspace_emptyBuffer_doesNothing() {
        var buffer = KeystrokeBuffer(capacity: 64)
        buffer.backspace()
        XCTAssertEqual(buffer.contents, "")
    }
}
