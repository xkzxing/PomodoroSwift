import Foundation

enum ToDoReorderDirection {
    case up
    case down
}

struct ToDoReorderEngine {
    static func rowTargetOffset(fromIndex: Int, toIndex: Int, items: [ToDoItem]) -> Int? {
        guard items.indices.contains(fromIndex), items.indices.contains(toIndex),
              items[fromIndex].isPinned == items[toIndex].isPinned else {
            return nil
        }
        return rowTargetOffset(fromIndex: fromIndex, toIndex: toIndex, itemCount: items.count)
    }

    static func insertionTargetOffset(fromIndex: Int, insertionIndex: Int, itemCount: Int) -> Int? {
        guard itemCount > 1 else { return nil }

        let normalizedFromIndex = clampedIndex(fromIndex, itemCount: itemCount)
        let normalizedInsertion = min(max(insertionIndex, 0), itemCount - 1)
        let rawOffset = normalizedInsertion > normalizedFromIndex ? (normalizedInsertion + 1) : normalizedInsertion
        return normalizedOffset(rawOffset, fromIndex: normalizedFromIndex, itemCount: itemCount)
    }

    static func rowTargetOffset(fromIndex: Int, toIndex: Int, itemCount: Int) -> Int? {
        guard itemCount > 1 else { return nil }

        let normalizedFromIndex = clampedIndex(fromIndex, itemCount: itemCount)
        let normalizedToIndex = clampedIndex(toIndex, itemCount: itemCount)

        guard normalizedFromIndex != normalizedToIndex else { return nil }

        let rawOffset = normalizedToIndex > normalizedFromIndex ? (normalizedToIndex + 1) : normalizedToIndex
        return normalizedOffset(rawOffset, fromIndex: normalizedFromIndex, itemCount: itemCount)
    }

    static func listEndOffset(fromIndex: Int, itemCount: Int) -> Int? {
        guard itemCount > 0 else { return nil }
        let normalizedFromIndex = clampedIndex(fromIndex, itemCount: itemCount)
        return normalizedOffset(itemCount, fromIndex: normalizedFromIndex, itemCount: itemCount)
    }

    static func adjacentOffset(fromIndex: Int, direction: ToDoReorderDirection, itemCount: Int) -> Int? {
        guard itemCount > 1 else { return nil }

        let normalizedFromIndex = clampedIndex(fromIndex, itemCount: itemCount)
        let rawOffset: Int

        switch direction {
        case .up:
            rawOffset = normalizedFromIndex - 1
        case .down:
            rawOffset = normalizedFromIndex + 2
        }

        return normalizedOffset(rawOffset, fromIndex: normalizedFromIndex, itemCount: itemCount)
    }

    private static func clampedIndex(_ index: Int, itemCount: Int) -> Int {
        min(max(index, 0), itemCount - 1)
    }

    private static func normalizedOffset(_ rawOffset: Int, fromIndex: Int, itemCount: Int) -> Int? {
        let clampedOffset = min(max(rawOffset, 0), itemCount)
        guard clampedOffset != fromIndex, clampedOffset != fromIndex + 1 else {
            return nil
        }
        return clampedOffset
    }
}
