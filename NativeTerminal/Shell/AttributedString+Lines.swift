import Foundation

extension AttributedString {
    /// The last `count` lines of the string.
    nonisolated func lastLines(_ count: Int) -> AttributedString {
        guard count > 0 else { return AttributedString() }
        var newlines = 0
        var index = endIndex
        while index > startIndex {
            let previous = characters.index(before: index)
            if characters[previous] == "\n" {
                newlines += 1
                if newlines == count { return AttributedString(self[index...]) }
            }
            index = previous
        }
        return self
    }
}
