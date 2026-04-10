@testable import Keyed
import XCTest

final class ImportServiceTests: XCTestCase {
    private var service: ImportService!

    override func setUp() {
        super.setUp()
        service = ImportService()
    }

    // MARK: - CSV Import

    func test_parseCSV_withUTF8BOM_stripsBOMAndParsesHeader() throws {
        // Regression for review §3 — Excel exports prefix UTF-8 files with a BOM and the
        // pre-fix parser silently failed to find the "abbreviation" header column.
        let csv = "\u{FEFF}abbreviation,expansion\n:email,test@example.com\n"
        let results = try service.parseCSV(csv)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].abbreviation, ":email")
        XCTAssertEqual(results[0].expansion, "test@example.com")
    }

    func test_parseCSV_basicTwoColumns_parsesCorrectly() throws {
        let csv = """
        abbreviation,expansion
        :email,test@example.com
        :sig,Best regards
        """
        let results = try service.parseCSV(csv)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].abbreviation, ":email")
        XCTAssertEqual(results[0].expansion, "test@example.com")
        XCTAssertEqual(results[1].abbreviation, ":sig")
        XCTAssertEqual(results[1].expansion, "Best regards")
    }

    func test_parseCSV_withLabelAndGroup_parsesAllColumns() throws {
        let csv = """
        abbreviation,expansion,label,group
        :email,test@example.com,Email address,Personal
        """
        let results = try service.parseCSV(csv)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].label, "Email address")
        XCTAssertEqual(results[0].groupName, "Personal")
    }

    func test_parseCSV_emptyString_returnsEmpty() throws {
        let results = try service.parseCSV("")
        XCTAssertTrue(results.isEmpty)
    }

    func test_parseCSV_headerOnly_returnsEmpty() throws {
        let results = try service.parseCSV("abbreviation,expansion")
        XCTAssertTrue(results.isEmpty)
    }

    func test_parseCSV_quotedFieldsWithCommas_parsesCorrectly() throws {
        let csv = """
        abbreviation,expansion
        :addr,"123 Main St, Apt 4"
        """
        let results = try service.parseCSV(csv)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].expansion, "123 Main St, Apt 4")
    }

    func test_parseCSV_escapedQuotes_parsesCorrectly() throws {
        let csv = "abbreviation,expansion\n:quote,\"He said \"\"hi\"\"\""
        let results = try service.parseCSV(csv)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].expansion, "He said \"hi\"")
    }

    func test_parseCSV_embeddedNewlinesInQuotedField_preserved() throws {
        let csv = "abbreviation,expansion\n:multi,\"line one\nline two\""
        let results = try service.parseCSV(csv)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].expansion, "line one\nline two")
    }

    func test_parseCSV_caseInsensitiveHeader_accepted() throws {
        let csv = """
        Abbreviation,Expansion
        :email,test@example.com
        """
        let results = try service.parseCSV(csv)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].abbreviation, ":email")
    }

    // MARK: - TextExpander Plist Import

    func test_parseTextExpanderPlist_parsesSnippets() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>groupInfo</key>
            <dict>
                <key>groupName</key>
                <string>My Snippets</string>
            </dict>
            <key>snippetsTE2</key>
            <array>
                <dict>
                    <key>abbreviation</key>
                    <string>:email</string>
                    <key>plainText</key>
                    <string>test@example.com</string>
                    <key>label</key>
                    <string>Email</string>
                </dict>
                <dict>
                    <key>abbreviation</key>
                    <string>:sig</string>
                    <key>plainText</key>
                    <string>Best regards</string>
                    <key>label</key>
                    <string>Signature</string>
                </dict>
            </array>
        </dict>
        </plist>
        """
        let data = try XCTUnwrap(plist.data(using: .utf8))
        let results = try service.parseTextExpanderPlist(data)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].abbreviation, ":email")
        XCTAssertEqual(results[0].expansion, "test@example.com")
        XCTAssertEqual(results[0].label, "Email")
        XCTAssertEqual(results[0].groupName, "My Snippets")
    }
}
