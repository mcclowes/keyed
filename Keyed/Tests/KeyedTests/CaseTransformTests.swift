@testable import Keyed
import XCTest

final class CaseTransformTests: XCTestCase {
    // MARK: - Detection

    func test_detect_exactMatch_returnsAsIs() {
        XCTAssertEqual(CaseTransform.detect(typed: ":email", abbreviation: ":email"), .asIs)
    }

    func test_detect_allCaps_returnsAllUpper() {
        XCTAssertEqual(CaseTransform.detect(typed: ":EMAIL", abbreviation: ":email"), .allUpper)
    }

    func test_detect_titleCase_returnsTitleCase() {
        XCTAssertEqual(CaseTransform.detect(typed: ":Email", abbreviation: ":email"), .titleCase)
    }

    func test_detect_noLetters_returnsAsIs() {
        XCTAssertEqual(CaseTransform.detect(typed: ":::", abbreviation: ":::"), .asIs)
    }

    func test_detect_lowercaseInput_returnsAsIs() {
        XCTAssertEqual(CaseTransform.detect(typed: ":sig", abbreviation: ":sig"), .asIs)
    }

    // MARK: - Application

    func test_apply_asIs_returnsOriginal() {
        XCTAssertEqual(CaseTransform.apply(.asIs, to: "test@example.com"), "test@example.com")
    }

    func test_apply_allUpper_returnsUppercased() {
        XCTAssertEqual(CaseTransform.apply(.allUpper, to: "Best regards"), "BEST REGARDS")
    }

    func test_apply_titleCase_capitalizesFirstLetterOnly() {
        XCTAssertEqual(CaseTransform.apply(.titleCase, to: "best regards"), "Best regards")
    }

    func test_apply_titleCase_preservesExistingCapsInRest() {
        // Previously this lowercased everything after the first letter. That destroyed intentional
        // capitalization like "Dr. Smith". Title case should only touch the first letter.
        XCTAssertEqual(CaseTransform.apply(.titleCase, to: "dr. Smith"), "Dr. Smith")
    }

    func test_apply_titleCase_firstNonLetterStaysUnchanged() {
        XCTAssertEqual(CaseTransform.apply(.titleCase, to: "$hello"), "$Hello")
    }
}
