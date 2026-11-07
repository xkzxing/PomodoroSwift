import Foundation

struct ToDoItem: Identifiable, Codable, Equatable {
    var id: UUID
    var text: String
    var isDone: Bool
    var isPinned: Bool
    var isInToday: Bool

    init(id: UUID = UUID(), text: String, isDone: Bool = false, isPinned: Bool = false, isInToday: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.isPinned = isPinned
        self.isInToday = isInToday
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, isDone, isPinned, isInToday
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        // Retain the legacy completion field solely for migration and compatibility.
        isDone = try values.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isInToday = try values.decodeIfPresent(Bool.self, forKey: .isInToday) ?? false
    }
}
