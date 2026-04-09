import XCTest
@testable import Keyed

final class ImportServiceTests: XCTestCase {
    private var service: ImportService!

    override func setUp() {
        super.setUp()
        service = ImportService()
    }

    // MARK: - CSV Import

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
        let data = plist.data(using: .utf8)!
        let results = try service.parseTextExpanderPlist(data)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].abbreviation, ":email")
        XCTAssertEqual(results[0].expansion, "test@example.com")
        XCTAssertEqual(results[0].label, "Email")
        XCTAssertEqual(results[0].groupName, "My Snippets")
    }
}
