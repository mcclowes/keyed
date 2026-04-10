import Foundation

struct ImportedSnippet {
    let abbreviation: String
    let expansion: String
    let label: String
    let groupName: String?
}

struct ImportService {
    // MARK: - CSV

    func parseCSV(_ content: String) throws -> [ImportedSnippet] {
        let rows = CSVTokenizer.rows(in: content)
        guard let header = rows.first else { return [] }

        let lowered = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let abbrevIndex = lowered.firstIndex(of: "abbreviation"),
              let expansionIndex = lowered.firstIndex(of: "expansion")
        else {
            throw ImportError.missingRequiredColumns
        }
        let labelIndex = lowered.firstIndex(of: "label")
        let groupIndex = lowered.firstIndex(of: "group")

        var imported: [ImportedSnippet] = []
        for row in rows.dropFirst() {
            guard row.count > max(abbrevIndex, expansionIndex) else { continue }
            let abbreviation = row[abbrevIndex]
            let expansion = row[expansionIndex]
            guard !abbreviation.isEmpty else { continue }
            let label = labelIndex.flatMap { $0 < row.count ? row[$0] : nil } ?? ""
            let groupName = groupIndex.flatMap { $0 < row.count ? row[$0] : nil }
            imported.append(ImportedSnippet(
                abbreviation: abbreviation,
                expansion: expansion,
                label: label,
                groupName: groupName
            ))
        }
        return imported
    }

    // MARK: - TextExpander Plist

    func parseTextExpanderPlist(_ data: Data) throws -> [ImportedSnippet] {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ImportError.invalidFormat
        }

        let groupName = (plist["groupInfo"] as? [String: Any])?["groupName"] as? String

        guard let snippets = plist["snippetsTE2"] as? [[String: Any]] else {
            throw ImportError.invalidFormat
        }

        return snippets.compactMap { dict in
            guard let abbreviation = dict["abbreviation"] as? String,
                  let expansion = dict["plainText"] as? String
            else {
                return nil
            }
            let label = dict["label"] as? String ?? ""
            return ImportedSnippet(abbreviation: abbreviation, expansion: expansion, label: label, groupName: groupName)
        }
    }
}

/// Tokenizes CSV text per RFC 4180: supports quoted fields, escaped quotes (""), embedded newlines.
enum CSVTokenizer {
    static func rows(in content: String) -> [[String]] {
        var state = ParserState()
        let chars = Array(content)
        var i = 0
        while i < chars.count {
            i = state.consume(chars: chars, at: i)
        }
        state.finalize()
        return state.rows
    }

    private struct ParserState {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        mutating func consume(chars: [Character], at index: Int) -> Int {
            let c = chars[index]
            if inQuotes {
                return consumeQuoted(c: c, chars: chars, at: index)
            }
            return consumeUnquoted(c: c, chars: chars, at: index)
        }

        private mutating func consumeQuoted(c: Character, chars: [Character], at index: Int) -> Int {
            if c != "\"" {
                currentField.append(c)
                return index + 1
            }
            if index + 1 < chars.count, chars[index + 1] == "\"" {
                currentField.append("\"")
                return index + 2
            }
            inQuotes = false
            return index + 1
        }

        private mutating func consumeUnquoted(c: Character, chars: [Character], at index: Int) -> Int {
            switch c {
            case "\"":
                inQuotes = true
                return index + 1
            case ",":
                commitField()
                return index + 1
            case "\r":
                commitRow()
                return (index + 1 < chars.count && chars[index + 1] == "\n") ? index + 2 : index + 1
            case "\n":
                commitRow()
                return index + 1
            default:
                currentField.append(c)
                return index + 1
            }
        }

        private mutating func commitField() {
            currentRow.append(currentField)
            currentField = ""
        }

        private mutating func commitRow() {
            commitField()
            if !currentRow.allSatisfy(\.isEmpty) {
                rows.append(currentRow)
            }
            currentRow = []
        }

        mutating func finalize() {
            guard !currentField.isEmpty || !currentRow.isEmpty else { return }
            commitRow()
        }
    }
}

enum ImportError: LocalizedError {
    case missingRequiredColumns
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .missingRequiredColumns:
            "CSV file must have 'abbreviation' and 'expansion' columns."
        case .invalidFormat:
            "File format is not recognized."
        }
    }
}
