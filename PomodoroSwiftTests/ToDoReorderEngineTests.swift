import XCTest
@testable import PomodoroSwift

final class ToDoReorderEngineTests: XCTestCase {
    func testInsertionTargetOffsetMovesItemDownIntoGap() {
        let offset = ToDoReorderEngine.insertionTargetOffset(fromIndex: 0, insertionIndex: 1, itemCount: 4)
        XCTAssertEqual(offset, 2)

        let reordered = applyMove(["A", "B", "C", "D"], from: 0, to: offset ?? -1)
        XCTAssertEqual(reordered, ["B", "A", "C", "D"])
    }

    func testInsertionTargetOffsetMovesItemUpIntoGap() {
        let offset = ToDoReorderEngine.insertionTargetOffset(fromIndex: 3, insertionIndex: 1, itemCount: 4)
        XCTAssertEqual(offset, 1)

        let reordered = applyMove(["A", "B", "C", "D"], from: 3, to: offset ?? -1)
        XCTAssertEqual(reordered, ["A", "D", "B", "C"])
    }

    func testRowTargetOffsetMovesItemDownIntoExpectedGap() {
        let offset = ToDoReorderEngine.rowTargetOffset(fromIndex: 0, toIndex: 1, itemCount: 4)
        XCTAssertEqual(offset, 2)

        let reordered = applyMove(["A", "B", "C", "D"], from: 0, to: offset ?? -1)
        XCTAssertEqual(reordered, ["B", "A", "C", "D"])
    }

    func testRowTargetOffsetMovesItemUpIntoExpectedGap() {
        let offset = ToDoReorderEngine.rowTargetOffset(fromIndex: 3, toIndex: 1, itemCount: 4)
        XCTAssertEqual(offset, 1)

        let reordered = applyMove(["A", "B", "C", "D"], from: 3, to: offset ?? -1)
        XCTAssertEqual(reordered, ["A", "D", "B", "C"])
    }

    func testTargetOffsetsClampAtTopAndBottom() {
        let topOffset = ToDoReorderEngine.rowTargetOffset(fromIndex: 2, toIndex: -100, itemCount: 4)
        XCTAssertEqual(topOffset, 0)

        let bottomOffset = ToDoReorderEngine.listEndOffset(fromIndex: 0, itemCount: 4)
        XCTAssertEqual(bottomOffset, 4)
    }

    func testNoOpMovesReturnNil() {
        XCTAssertNil(ToDoReorderEngine.insertionTargetOffset(fromIndex: 0, insertionIndex: 0, itemCount: 4))
        XCTAssertNil(ToDoReorderEngine.rowTargetOffset(fromIndex: 1, toIndex: 1, itemCount: 4))
        XCTAssertNil(ToDoReorderEngine.listEndOffset(fromIndex: 3, itemCount: 4))
        XCTAssertNil(ToDoReorderEngine.adjacentOffset(fromIndex: 0, direction: .up, itemCount: 4))
        XCTAssertNil(ToDoReorderEngine.adjacentOffset(fromIndex: 3, direction: .down, itemCount: 4))
    }

    private func applyMove(_ values: [String], from: Int, to: Int) -> [String] {
        guard values.indices.contains(from), to >= 0, to <= values.count else {
            return values
        }

        var reordered = values
        let moved = reordered.remove(at: from)
        let destinationIndex = to > from ? (to - 1) : to
        reordered.insert(moved, at: destinationIndex)
        return reordered
    }
}
