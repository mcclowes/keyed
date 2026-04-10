import Foundation

/// A small, generally-useful starter set seeded on first launch so the app isn't empty.
/// Users can edit or delete any of these; they're only inserted once.
enum DefaultSnippets {
    struct Entry {
        let abbreviation: String
        let expansion: String
        let label: String
    }

    static let entries: [Entry] = [
        // Dates & times — use the built-in placeholders
        Entry(abbreviation: ";date", expansion: "{date}", label: "Today's date"),
        Entry(abbreviation: ";time", expansion: "{time}", label: "Current time"),
        Entry(abbreviation: ";dt", expansion: "{datetime}", label: "Date and time"),

        // Common typography
        Entry(abbreviation: ";em", expansion: "—", label: "Em dash"),
        Entry(abbreviation: ";el", expansion: "…", label: "Ellipsis"),
        Entry(abbreviation: ";deg", expansion: "°", label: "Degree sign"),
        Entry(abbreviation: ";tm", expansion: "™", label: "Trademark"),
        Entry(abbreviation: ";cp", expansion: "©", label: "Copyright"),
        Entry(abbreviation: ";rr", expansion: "®", label: "Registered"),

        // Arrows
        Entry(abbreviation: ";arr", expansion: "→", label: "Right arrow"),
        Entry(abbreviation: ";larr", expansion: "←", label: "Left arrow"),

        // Fun
        Entry(abbreviation: ";shrug", expansion: #"¯\_(ツ)_/¯"#, label: "Shrug"),

        // Editable templates — {cursor} drops the caret where the user starts typing
        Entry(
            abbreviation: ";sig",
            expansion: "Best,\n{cursor}",
            label: "Email signature (edit me)"
        ),
        Entry(
            abbreviation: ";ty",
            expansion: "Thank you{cursor}!",
            label: "Thank you"
        ),
    ]
}
