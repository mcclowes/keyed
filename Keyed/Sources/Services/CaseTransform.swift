import Foundation

enum CasePattern {
    case asIs
    case allUpper
    case titleCase
}

enum CaseTransform {
    static func detect(typed: String, abbreviation: String) -> CasePattern {
        let typedLetters = typed.filter(\.isLetter)
        guard !typedLetters.isEmpty else { return .asIs }

        if typedLetters == typedLetters.uppercased(), typedLetters != typedLetters.lowercased() {
            return .allUpper
        }

        if let first = typedLetters.first, first.isUppercase {
            let abbrevLetters = abbreviation.filter(\.isLetter)
            let typedRest = String(typedLetters.dropFirst())
            let abbrevRest = String(abbrevLetters.dropFirst())
            if typedRest.lowercased() == abbrevRest.lowercased() {
                return .titleCase
            }
        }

        return .asIs
    }

    static func apply(_ pattern: CasePattern, to text: String) -> String {
        switch pattern {
        case .asIs:
            text
        case .allUpper:
            text.uppercased()
        case .titleCase:
            capitalizingFirstLetter(text)
        }
    }

    /// Uppercases only the first letter in the text; all other characters are preserved as-is.
    private static func capitalizingFirstLetter(_ text: String) -> String {
        guard let firstLetterIndex = text.firstIndex(where: \.isLetter) else { return text }
        var result = text
        let letter = result[firstLetterIndex]
        result.replaceSubrange(firstLetterIndex...firstLetterIndex, with: String(letter).uppercased())
        return result
    }
}
