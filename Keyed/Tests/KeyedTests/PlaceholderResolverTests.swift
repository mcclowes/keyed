@testable import Keyed
import XCTest

final class PlaceholderResolverTests: XCTestCase {
    private let resolver = PlaceholderResolver()

    func test_resolve_datePlaceholder_replacesWithCurrentDate() {
        let result = resolver.resolve("Today is {date}")
        XCTAssertFalse(result.contains("{date}"))
        XCTAssertTrue(result.contains("Today is "))
        // Contains a year (4 digits)
        XCTAssertTrue(result.range(of: "\\d{4}", options: .regularExpression) != nil)
    }

    func test_resolve_timePlaceholder_replacesWithCurrentTime() {
        let result = resolver.resolve("Now: {time}")
        XCTAssertFalse(result.contains("{time}"))
        XCTAssertTrue(result.contains("Now: "))
    }

    func test_resolve_datetimePlaceholder_replacesWithBoth() {
        let result = resolver.resolve("Logged at {datetime}")
        XCTAssertFalse(result.contains("{datetime}"))
    }

    func test_resolve_noPlaceholders_returnsOriginal() {
        let text = "Hello, world!"
        XCTAssertEqual(resolver.resolve(text), text)
    }

    func test_resolve_multiplePlaceholders_replacesAll() {
        let result = resolver.resolve("{date} at {time}")
        XCTAssertFalse(result.contains("{date}"))
        XCTAssertFalse(result.contains("{time}"))
    }

    // MARK: - Cursor

    func test_resolveWithCursor_withCursor_returnsCharsAfterCursor() {
        let resolved = resolver.resolveWithCursor("Hello {cursor}, world!")
        XCTAssertEqual(resolved.text, "Hello , world!")
        XCTAssertEqual(resolved.cursorOffset, ", world!".count)
    }

    func test_resolveWithCursor_noCursor_returnsNilOffset() {
        let resolved = resolver.resolveWithCursor("Hello world")
        XCTAssertEqual(resolved.text, "Hello world")
        XCTAssertNil(resolved.cursorOffset)
    }

    func test_resolveWithCursor_cursorAtEnd_returnsZero() {
        let resolved = resolver.resolveWithCursor("Hello{cursor}")
        XCTAssertEqual(resolved.text, "Hello")
        XCTAssertEqual(resolved.cursorOffset, 0)
    }

    func test_resolveWithCursor_stripsCursor_fromMiddle() {
        let resolved = resolver.resolveWithCursor("Hi {cursor}, thanks")
        XCTAssertEqual(resolved.text, "Hi , thanks")
        XCTAssertEqual(resolved.cursorOffset, ", thanks".count)
    }

    // MARK: - Cursor + placeholder interaction (regression test for review §1.2)

    func test_resolveWithCursor_cursorAfterDate_offsetMeasuredAgainstResolvedText() {
        // Cursor sits between a resolved date and a short tail. The offset must be
        // counted against the RESOLVED string so the caret lands immediately after
        // the date regardless of how long the date rendered.
        let resolved = resolver.resolveWithCursor("Date: {date} {cursor}end")
        XCTAssertNil(resolved.text.range(of: "{date}"))
        XCTAssertNil(resolved.text.range(of: "{cursor}"))
        XCTAssertEqual(resolved.cursorOffset, "end".count)
        XCTAssertTrue(resolved.text.hasSuffix("end"))
    }
}
