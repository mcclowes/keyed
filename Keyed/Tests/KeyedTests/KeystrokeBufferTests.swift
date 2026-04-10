@testable import Keyed
import XCTest

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

    // MARK: - Longest match

    func test_longestMatch_prefersLongerCandidate() {
        var buffer = KeystrokeBuffer(capacity: 64)
        for char in ":signature" {
            buffer.append(String(char))
        }
        // Passed in descending-length order, as the engine does.
        let sorted = [":signature", ":sig"]
        XCTAssertEqual(buffer.longestSuffixMatch(in: sorted), ":signature")
    }

    func test_longestMatch_fallsBackToCaseInsensitive() {
        var buffer = KeystrokeBuffer(capacity: 64)
        for char in ":EMAIL" {
            buffer.append(String(char))
        }
        XCTAssertEqual(buffer.longestSuffixMatch(in: [":email"]), ":email")
    }

    // MARK: - Word boundary

    func test_wordBoundary_atStartOfBuffer_returnsTrue() {
        var buffer = KeystrokeBuffer(capacity: 64)
        for char in "foo" {
            buffer.append(String(char))
        }
        XCTAssertTrue(buffer.hasWordBoundaryBefore(suffixLength: 3))
    }

    func test_wordBoundary_afterLetter_returnsFalse() {
        var buffer = KeystrokeBuffer(capacity: 64)
        for char in "xfoo" {
            buffer.append(String(char))
        }
        XCTAssertFalse(buffer.hasWordBoundaryBefore(suffixLength: 3))
    }

    func test_wordBoundary_afterSpace_returnsTrue() {
        var buffer = KeystrokeBuffer(capacity: 64)
        for char in "x foo" {
            buffer.append(String(char))
        }
        XCTAssertTrue(buffer.hasWordBoundaryBefore(suffixLength: 3))
    }

    func test_wordBoundary_afterPunctuation_returnsTrue() {
        var buffer = KeystrokeBuffer(capacity: 64)
        for char in "hello.foo" {
            buffer.append(String(char))
        }
        XCTAssertTrue(buffer.hasWordBoundaryBefore(suffixLength: 3))
    }

    func test_wordBoundary_atStartOfWrappedBuffer_returnsFalse() {
        // Fill the buffer to its exact capacity so the oldest position still holds a real
        // typed character and suffixLength == size. Without overflow tracking, the buffer
        // answered "yes, that's a word boundary" — now it correctly answers "no" once the
        // ring has wrapped.
        var buffer = KeystrokeBuffer(capacity: 4)
        // Overflow the buffer so hasWrapped flips.
        for char in "abcde" {
            buffer.append(String(char))
        }
        // Contents: "bcde", suffixLength == 4 fills the buffer.
        XCTAssertEqual(buffer.contents, "bcde")
        XCTAssertFalse(buffer.hasWordBoundaryBefore(suffixLength: 4))
    }

    func test_wordBoundary_afterResetPostOverflow_returnsTrue() {
        // reset() must clear the wrapped flag — otherwise a clean buffer stays stuck.
        var buffer = KeystrokeBuffer(capacity: 4)
        for char in "abcde" {
            buffer.append(String(char))
        }
        buffer.reset()
        for char in "foo" {
            buffer.append(String(char))
        }
        XCTAssertTrue(buffer.hasWordBoundaryBefore(suffixLength: 3))
    }

    // MARK: - Longest match with mixed case

    func test_longestSuffixMatch_prefersLongerCaseInsensitiveOverShorterSameCandidate() {
        // Buffer content " abcdef" — the longer candidate "abCDef" matches only
        // case-insensitively, but still beats the shorter exact-case candidate "CD" (which
        // doesn't match the tail anyway). Verifies the two-pass walk returns the longest
        // matching candidate under the insensitive pass.
        var buffer = KeystrokeBuffer(capacity: 64)
        for char in " abcdef" {
            buffer.append(String(char))
        }
        let candidates = ["abCDef", "CD"]
        XCTAssertEqual(buffer.longestSuffixMatch(in: candidates), "abCDef")
    }

    func test_longestSuffixMatch_exactCasePreferredAtSameLength() {
        // At equal length, exact-case match wins regardless of candidate ordering — the
        // exact-case pass runs first and short-circuits before the insensitive pass.
        var buffer = KeystrokeBuffer(capacity: 64)
        for char in " foo" {
            buffer.append(String(char))
        }
        let candidates = ["FOO", "foo"]
        XCTAssertEqual(buffer.longestSuffixMatch(in: candidates), "foo")
    }

    // MARK: - Unicode

    func test_unicode_nonAscii_matches() {
        var buffer = KeystrokeBuffer(capacity: 64)
        for char in ":café" {
            buffer.append(String(char))
        }
        XCTAssertTrue(buffer.hasSuffix(":café"))
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
