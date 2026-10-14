import Foundation

nonisolated struct Cell: Hashable, Sendable {
    var character: Character
    var style: TextStyle

    static let blank = Cell(character: " ", style: .plain)
}
