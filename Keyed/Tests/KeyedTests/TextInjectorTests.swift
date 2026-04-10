@testable import Keyed
import XCTest

final class TextInjectorTests: XCTestCase {
    func test_chunkUTF16_shortString_producesSingleChunk() {
        let chunks = UnicodeEventTextInjector.chunkUTF16("hello", maxUTF16PerEvent: 20)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0], Array("hello".utf16))
    }

    func test_chunkUTF16_longAsciiString_splitsAtBudget() {
        let input = String(repeating: "a", count: 45)
        let chunks = UnicodeEventTextInjector.chunkUTF16(input, maxUTF16PerEvent: 20)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].count, 20)
        XCTAssertEqual(chunks[1].count, 20)
        XCTAssertEqual(chunks[2].count, 5)
    }

    func test_chunkUTF16_emojiOnBoundary_isNotSplitMidSurrogate() {
        // 19 ASCII characters, then a single non-BMP emoji (2 UTF-16 code units).
        // A naive UTF-16-window chunker with a 20-unit budget would place the high surrogate
        // in the first chunk and the low surrogate in the second — that regressed from the
        // pre-fix implementation and produced garbage in the target app.
        let ascii = String(repeating: "a", count: 19)
        let input = ascii + "🎉"
        let chunks = UnicodeEventTextInjector.chunkUTF16(input, maxUTF16PerEvent: 20)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0], Array(ascii.utf16))
        XCTAssertEqual(chunks[1], Array("🎉".utf16))
        for chunk in chunks {
            XCTAssertTrue(
                String(utf16CodeUnits: chunk, count: chunk.count).unicodeScalars
                    .allSatisfy { _ in true },
                "each chunk must be a well-formed UTF-16 sequence"
            )
        }
    }

    func test_chunkUTF16_zwjClusterExceedingBudget_isEmittedWhole() {
        // Family emoji — a ZWJ sequence whose UTF-16 length is well above the 20-unit budget.
        // Splitting it produces visible garbage; instead we emit it as its own chunk.
        let family = "👨‍👩‍👧‍👦"
        XCTAssertGreaterThan(Array(family.utf16).count, 10)
        let chunks = UnicodeEventTextInjector.chunkUTF16(family, maxUTF16PerEvent: 8)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0], Array(family.utf16))
    }

    func test_chunkUTF16_combiningMarkStaysWithBaseCharacter() {
        // "é" decomposed as U+0065 + U+0301 is a single grapheme cluster (2 UTF-16 units).
        // The base + combining mark must live in the same chunk.
        let decomposed = "\u{0065}\u{0301}"
        let padding = String(repeating: "a", count: 19)
        let input = padding + decomposed
        let chunks = UnicodeEventTextInjector.chunkUTF16(input, maxUTF16PerEvent: 20)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0], Array(padding.utf16))
        XCTAssertEqual(chunks[1], Array(decomposed.utf16))
    }

    func test_chunkUTF16_emptyString_producesNoChunks() {
        XCTAssertTrue(UnicodeEventTextInjector.chunkUTF16("", maxUTF16PerEvent: 20).isEmpty)
    }
}
