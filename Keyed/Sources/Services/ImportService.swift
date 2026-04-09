import Foundation

struct ImportedSnippet: Sendable {
    let abbreviation: String
    let expansion: String
    let label: String
    let groupName: String?
}

struct ImportService: Sendable {

    // MARK: - CSV

    func parseCSV(_ content: String) throws -> [ImportedSnippet] {
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { return [] }

        let header = parseCSVLine(lines[0])
        let abbrevIndex = header.firstIndex(of: "abbreviation")
        let expansionIndex = header.firstIndex(of: "expansion")

        guard let abbrevIndex, let expansionIndex else {
            throw ImportError.missingRequiredColumns
        }

        let labelIndex = header.firstIndex(of: "label")
        let groupIndex = header.firstIndex(of: "group")

        return lines.dropFirst().compactMap { line in
            let fields = parseCSVLine(line)
            guard fields.count > max(abbrevIndex, expansionIndex) else { return nil }
            let abbreviation = fields[abbrevIndex]
            let expansion = fields[expansionIndex]
            guard !abbreviation.isEmpty else { return nil }

            let label = labelIndex.flatMap { $0 < fields.count ? fields[$0] : nil } ?? ""
            let groupName = groupIndex.flatMap { $0 < fields.count ? fields[$0] : nil }

            return ImportedSnippet(abbreviation: abbreviation, expansion: expansion, label: label, groupName: groupName)
        }
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
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
                  let expansion = dict["plainText"] as? String else {
                return nil
            }
            let label = dict["label"] as? String ?? ""
            return ImportedSnippet(abbreviation: abbreviation, expansion: expansion, label: label, groupName: groupName)
        }
    }
}

enum ImportError: LocalizedError {
    case missingRequiredColumns
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .missingRequiredColumns:
            return "CSV file must have 'abbreviation' and 'expansion' columns."
        case .invalidFormat:
            return "File format is not recognized."
        }
    }
}
