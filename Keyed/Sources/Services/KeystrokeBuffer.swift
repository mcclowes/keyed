import Foundation

/// Ring buffer of typed characters used for suffix matching against known abbreviations.
struct KeystrokeBuffer {
    private var storage: [Character]
    private var head: Int = 0
    private var size: Int = 0
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        storage = Array(repeating: Character(" "), count: capacity)
    }

    mutating func append(_ character: String) {
        for scalarChar in character {
            appendCharacter(scalarChar)
        }
    }

    private mutating func appendCharacter(_ character: Character) {
        let index = (head + size) % capacity
        if size < capacity {
            storage[index] = character
            size += 1
        } else {
            storage[head] = character
            head = (head + 1) % capacity
        }
    }

    mutating func backspace() {
        guard !isEmpty else { return }
        size -= 1
    }

    var isEmpty: Bool {
        size == 0
    }

    mutating func reset() {
        head = 0
        size = 0
    }

    var contents: String {
        var result = ""
        result.reserveCapacity(size)
        for i in 0..<size {
            result.append(storage[(head + i) % capacity])
        }
        return result
    }

    func hasSuffix(_ abbreviation: String) -> Bool {
        suffixMatches(abbreviation, caseInsensitive: false)
    }

    func hasSuffixCaseInsensitive(_ abbreviation: String) -> Bool {
        suffixMatches(abbreviation, caseInsensitive: true)
    }

    private func suffixMatches(_ abbreviation: String, caseInsensitive: Bool) -> Bool {
        let abbrevChars = Array(abbreviation)
        let abbrevCount = abbrevChars.count
        guard abbrevCount <= size else { return false }

        for i in 0..<abbrevCount {
            let bufferIndex = (head + size - abbrevCount + i) % capacity
            let lhs = storage[bufferIndex]
            let rhs = abbrevChars[i]
            if caseInsensitive {
                if String(lhs).lowercased() != String(rhs).lowercased() { return false }
            } else {
                if lhs != rhs { return false }
            }
        }
        return true
    }

    /// Returns the typed text matching the tail of the buffer for the given abbreviation length.
    func typedSuffix(length: Int) -> String {
        guard length <= size else { return "" }
        var result = ""
        result.reserveCapacity(length)
        for i in 0..<length {
            let bufferIndex = (head + size - length + i) % capacity
            result.append(storage[bufferIndex])
        }
        return result
    }

    func firstMatch(from abbreviations: Set<String>) -> String? {
        abbreviations.first { hasSuffix($0) }
    }

    func firstMatchCaseInsensitive(from abbreviations: Set<String>) -> String? {
        abbreviations.first { hasSuffixCaseInsensitive($0) }
    }

    /// Walks candidates in order and returns the first whose suffix matches the buffer.
    /// Callers are expected to pass abbreviations sorted by descending length so the longest match wins.
    func longestSuffixMatch(in candidates: [String]) -> String? {
        for candidate in candidates where hasSuffix(candidate) {
            return candidate
        }
        for candidate in candidates where hasSuffixCaseInsensitive(candidate) {
            return candidate
        }
        return nil
    }

    /// Returns true when the character immediately preceding the given suffix is a word boundary,
    /// or when the suffix sits at the start of the buffer. A word boundary is any non-alphanumeric character.
    func hasWordBoundaryBefore(suffixLength: Int) -> Bool {
        guard suffixLength > 0, suffixLength <= size else { return false }
        let boundaryPosition = size - suffixLength
        if boundaryPosition == 0 { return true }
        let bufferIndex = (head + boundaryPosition - 1) % capacity
        let precedingChar = storage[bufferIndex]
        return !precedingChar.isLetter && !precedingChar.isNumber
    }
}
