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

    func test_cursorOffset_withCursor_returnsCharsAfterCursor() {
        let text = "Hello {cursor}, world!"
        let offset = resolver.cursorOffset(in: text)
        XCTAssertEqual(offset, ", world!".count)
    }

    func test_cursorOffset_noCursor_returnsNil() {
        XCTAssertNil(resolver.cursorOffset(in: "Hello world"))
    }

    func test_cursorOffset_cursorAtEnd_returnsZero() {
        XCTAssertEqual(resolver.cursorOffset(in: "Hello{cursor}"), 0)
    }

    func test_stripCursorPlaceholder_removesCursor() {
        XCTAssertEqual(resolver.stripCursorPlaceholder("Hi {cursor}, thanks"), "Hi , thanks")
    }
}
