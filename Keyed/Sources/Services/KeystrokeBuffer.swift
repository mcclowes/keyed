import Foundation

/// Ring buffer of typed characters used for suffix matching against known abbreviations.
struct KeystrokeBuffer {
    private var storage: [Character]
    private var head: Int = 0
    private var size: Int = 0
    /// Set to true the first time the buffer overflows. Once the ring has wrapped we can no
    /// longer trust that "the suffix fills the entire buffer" means "the suffix starts a new
    /// word" — the oldest slot holds whatever the user typed 128 characters ago, and that
    /// is almost certainly in the middle of a word. We track this so the word-boundary check
    /// can reject overflowed matches conservatively.
    private var hasWrapped: Bool = false
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
            hasWrapped = true
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
        hasWrapped = false
    }

    var contents: String {
        var result = ""
        result.reserveCapacity(size)
        for i in 0..<size {
            result.append(storage[(head + i) % capacity])
        }
        return result
    }

    func hasSuffix(_ abbreviation: String, endOffset: Int = 0) -> Bool {
        suffixMatches(abbreviation, caseInsensitive: false, endOffset: endOffset)
    }

    func hasSuffixCaseInsensitive(_ abbreviation: String, endOffset: Int = 0) -> Bool {
        suffixMatches(abbreviation, caseInsensitive: true, endOffset: endOffset)
    }

    /// `endOffset` lets callers match against a window ending N characters before the tail —
    /// used when the most recently typed character is a delimiter and the abbreviation sits
    /// just behind it.
    private func suffixMatches(_ abbreviation: String, caseInsensitive: Bool, endOffset: Int) -> Bool {
        let abbrevChars = Array(abbreviation)
        let abbrevCount = abbrevChars.count
        let effectiveSize = size - endOffset
        guard endOffset >= 0, abbrevCount <= effectiveSize else { return false }

        for i in 0..<abbrevCount {
            let bufferIndex = (head + effectiveSize - abbrevCount + i) % capacity
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
    /// `endOffset` skips the final N characters when the caller has a delimiter trailing the abbreviation.
    func typedSuffix(length: Int, endOffset: Int = 0) -> String {
        let effectiveSize = size - endOffset
        guard endOffset >= 0, length <= effectiveSize else { return "" }
        var result = ""
        result.reserveCapacity(length)
        for i in 0..<length {
            let bufferIndex = (head + effectiveSize - length + i) % capacity
            result.append(storage[bufferIndex])
        }
        return result
    }

    /// Returns the longest candidate whose suffix matches the buffer, preferring an exact-case
    /// match over a case-insensitive one at the same length. Callers must pass `candidates`
    /// sorted by descending length: the two-pass walk relies on that ordering to guarantee
    /// the longest match wins under each comparator.
    ///
    /// Two passes (exact then insensitive) rather than a single interleaved walk so that
    /// `["ABC", "abc"]` on input `"abc"` returns `"abc"` (exact) rather than whichever
    /// candidate happened to come first in the list.
    func longestSuffixMatch(in candidates: [String], endOffset: Int = 0) -> String? {
        for candidate in candidates where hasSuffix(candidate, endOffset: endOffset) {
            return candidate
        }
        for candidate in candidates where hasSuffixCaseInsensitive(candidate, endOffset: endOffset) {
            return candidate
        }
        return nil
    }

    /// Returns true when the character immediately preceding the given suffix is a word boundary,
    /// or when the suffix sits at the start of the buffer. A word boundary is any non-alphanumeric character.
    ///
    /// Once the ring has wrapped, "suffix starts at the oldest slot" no longer means "suffix starts
    /// at the beginning of input" — so we reject that case rather than risk a false expansion that
    /// lands in the middle of a word.
    func hasWordBoundaryBefore(suffixLength: Int, endOffset: Int = 0) -> Bool {
        let effectiveSize = size - endOffset
        guard endOffset >= 0, suffixLength > 0, suffixLength <= effectiveSize else { return false }
        let boundaryPosition = effectiveSize - suffixLength
        if boundaryPosition == 0 {
            return !hasWrapped
        }
        let bufferIndex = (head + boundaryPosition - 1) % capacity
        let precedingChar = storage[bufferIndex]
        return !precedingChar.isLetter && !precedingChar.isNumber
    }
}
