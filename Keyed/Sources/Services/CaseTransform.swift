import Foundation

enum CasePattern {
    case asIs
    case allUpper
    case titleCase
}

enum CaseTransform {
    static func detect(typed: String, abbreviation: String) -> CasePattern {
        // Only detect case changes for the letter characters
        let typedLetters = typed.filter(\.isLetter)
        guard !typedLetters.isEmpty else { return .asIs }

        if typedLetters == typedLetters.uppercased(), typedLetters != typedLetters.lowercased() {
            return .allUpper
        }

        // Title case: first letter uppercase, rest matches original abbreviation pattern
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
            titleCase(text)
        }
    }

    private static func titleCase(_ text: String) -> String {
        // Capitalize first letter of each sentence/line, lowercase the rest
        guard let first = text.first else { return text }
        return String(first).uppercased() + text.dropFirst().lowercased()
    }
}
