import Foundation

struct KeystrokeBuffer: Sendable {
    private var storage: [String]
    private var head: Int = 0
    private var count: Int = 0
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        self.storage = Array(repeating: "", count: capacity)
    }

    mutating func append(_ character: String) {
        let index = (head + count) % capacity
        if count < capacity {
            storage[index] = character
            count += 1
        } else {
            storage[head] = character
            head = (head + 1) % capacity
        }
    }

    mutating func backspace() {
        guard count > 0 else { return }
        count -= 1
    }

    mutating func reset() {
        head = 0
        count = 0
    }

    var contents: String {
        var result = ""
        result.reserveCapacity(count)
        for i in 0..<count {
            result += storage[(head + i) % capacity]
        }
        return result
    }

    func hasSuffix(_ abbreviation: String) -> Bool {
        let abbrevChars = Array(abbreviation)
        guard abbrevChars.count <= count else { return false }

        for i in 0..<abbrevChars.count {
            let bufferIndex = (head + count - abbrevChars.count + i) % capacity
            guard storage[bufferIndex] == String(abbrevChars[i]) else { return false }
        }
        return true
    }

    func firstMatch(from abbreviations: Set<String>) -> String? {
        abbreviations.first { hasSuffix($0) }
    }
}
