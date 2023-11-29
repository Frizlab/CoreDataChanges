import Foundation
import XCTest

@testable import CoreDataChanges



final class CoreDataChangesAggregatorSingleSectionTests : XCTestCase {
	
	func testBasicInsert() {
		let aggregator = CoreDataChangesAggregator<String>()
		
		let tested   = Ref("abc" .toTestInput())
		let expected =     "a1bc".toTestInput()
		aggregator.addInsert(atIndex: 1, object: "1")
		
		aggregator.iterateAggregatedChanges(aggregatorHandler(for: tested))
		XCTAssertEqual(tested.value.joined(), expected.joined())
	}
	
	func testBasicDelete() {
		let aggregator = CoreDataChangesAggregator<String>()
		
		let tested   = Ref("abc".toTestInput())
		let expected =     "ac" .toTestInput()
		aggregator.addDelete(atIndex: 1)
		
		aggregator.iterateAggregatedChanges(aggregatorHandler(for: tested))
		XCTAssertEqual(tested.value.joined(), expected.joined())
	}
	
	func testTwoInserts() {
		let aggregator = CoreDataChangesAggregator<String>()
		
		let tested   = Ref("abc"  .toTestInput())
		let expected =     "a1b3c".toTestInput()
		aggregator.addInsert(atIndex: 1, object: "1")
		aggregator.addInsert(atIndex: 3, object: "3")
		
		aggregator.iterateAggregatedChanges(aggregatorHandler(for: tested))
		XCTAssertEqual(tested.value.joined(), expected.joined())
	}
	
	func testTwoDeletes() {
		let aggregator = CoreDataChangesAggregator<String>()
		
		let tested   = Ref("abc".toTestInput())
		let expected =     "a"  .toTestInput()
		aggregator.addDelete(atIndex: 1)
		aggregator.addDelete(atIndex: 2)
		
		aggregator.iterateAggregatedChanges(aggregatorHandler(for: tested))
		XCTAssertEqual(tested.value.joined(), expected.joined())
	}
	
	func testBasicMove() {
		let aggregator = CoreDataChangesAggregator<String>()
		
		let tested   = Ref("abc".toTestInput())
		let expected =     "cab".toTestInput()
		aggregator.addMove(from: 2, to: 0)
		
		aggregator.iterateAggregatedChanges(aggregatorHandler(for: tested))
		XCTAssertEqual(tested.value.joined(), expected.joined())
	}
	
	func testBasicTwoInsertsTwoFalseMoves() {
		let aggregator = CoreDataChangesAggregator<String>()
		
		let tested   = Ref("ca"  .toTestInput())
		let expected =     "dcba".toTestInput()
		aggregator.addInsert(atIndex: 2, object: "b")
		aggregator.addInsert(atIndex: 0, object: "d")
		aggregator.addMove(from: 0, to: 1)
		aggregator.addMove(from: 1, to: 3)
		
		aggregator.iterateAggregatedChanges(aggregatorHandler(for: tested))
		XCTAssertEqual(tested.value.joined(), expected.joined())
	}
	
	func testBasicTwoDeletesTwoFalseMoves() {
		let aggregator = CoreDataChangesAggregator<String>()
		
		let tested   = Ref("dcba".toTestInput())
		let expected =     "ca"  .toTestInput()
		aggregator.addMove(from: 1, to: 0)
		aggregator.addMove(from: 3, to: 1)
		aggregator.addDelete(atIndex: 2)
		aggregator.addDelete(atIndex: 0)
		
		aggregator.iterateAggregatedChanges(aggregatorHandler(for: tested))
		XCTAssertEqual(tested.value.joined(), expected.joined())
	}
	
	func testInsertAndMoveAfterInsert() {
		let aggregator = CoreDataChangesAggregator<String>()
		
		let tested   = Ref("abc" .toTestInput())
		let expected =     "a1cb".toTestInput()
		aggregator.addInsert(atIndex: 1, object: "1")
		aggregator.addMove(from: 2, to: 2)
		
		aggregator.iterateAggregatedChanges(aggregatorHandler(for: tested))
		XCTAssertEqual(tested.value.joined(), expected.joined())
	}
	
	func testInsertAndMoveFromBeforeToAfterInsert() {
		let aggregator = CoreDataChangesAggregator<String>()
		
		let tested   = Ref("abc" .toTestInput())
		let expected =     "b1ac".toTestInput()
		aggregator.addInsert(atIndex: 1, object: "1")
		aggregator.addMove(from: 0, to: 2)
		
		aggregator.iterateAggregatedChanges(aggregatorHandler(for: tested))
		XCTAssertEqual(tested.value.joined(), expected.joined())
	}
	
	func testInsertAndMoveFromAfterToBeforeInsert() {
		let aggregator = CoreDataChangesAggregator<String>()
		
		let tested   = Ref("abc" .toTestInput())
		let expected =     "c1ab".toTestInput()
		aggregator.addInsert(atIndex: 1, object: "1")
		aggregator.addMove(from: 2, to: 0)
		
		aggregator.iterateAggregatedChanges(aggregatorHandler(for: tested))
		XCTAssertEqual(tested.value.joined(), expected.joined())
	}
	
	func testMoveFromSrcToSameDst() {
		let aggregator = CoreDataChangesAggregator<String>()
		
		let tested   = Ref("abc".toTestInput())
		let expected =     "abc".toTestInput()
		/* This case should not happen from CoreData, but it might.
		 * Interestingly we get a move from the same source and destination in the aggregator handler
		 *  (obviously in this case, but it is interesting to know this situation can happen). */
		aggregator.addMove(from: 1, to: 1)
		
		aggregator.iterateAggregatedChanges(aggregatorHandler(for: tested))
		XCTAssertEqual(tested.value.joined(), expected.joined())
	}
	
	private func aggregatorHandler(for input: Ref<[String]>) -> (AggregatedCoreDataChange<String>) -> Void {
		return { change in
			switch change {
				case let .row(.insert(destPath), element):   input.value.insert(element, at: destPath.rowIdx)
				case let .row(.delete(sourcePath), _): input.value.remove(at: sourcePath.rowIdx)
				case let .row(.move(sourcePath, destPath), _):
					let element = input.value[sourcePath.rowIdx]
					input.value.remove(at: sourcePath.rowIdx)
					input.value.insert(element, at: destPath.rowIdx)
				case .row(.update, _), .section:
					(/*nop*/)
			}
		}
	}
	
}


private extension CoreDataChangesAggregator where RowItemID == String {
	
	func addDelete(atIndex idx: Int) {
		addChange(.delete, atIndexPath: [0, idx], newIndexPath: nil, for: "invalid deleted object (object is unneeded and getting the actual value is not trivial so we put an obviously invalid value)")
	}
	
	func addInsert(atIndex idx: Int, object: String) {
		addChange(.insert, atIndexPath: nil, newIndexPath: [0, idx], for: object)
	}
	
	func addMove(from sourceIdx: Int, to destIdx: Int) {
		addChange(.move, atIndexPath: [0, sourceIdx], newIndexPath: [0, destIdx], for: "invalid moved object (object is unneeded and getting the actual value is not trivial so we put an obviously invalid value)")
	}
	
}


private final class Ref<T> {
	
	var value: T
	
	init(_ v: T) {
		value = v
	}
	
}


private extension String {
	
	func toTestInput() -> [String] {
		return map(String.init)
	}
	
}
