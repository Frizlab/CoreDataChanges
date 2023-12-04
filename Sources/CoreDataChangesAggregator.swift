import enum CoreData.NSFetchedResultsChangeType
import Foundation
import os.log



public final class CoreDataChangesAggregator<RowItemID> {
	
	public init() {
	}
	
	public func addSectionChange(_ changeType: NSFetchedResultsChangeType, atSectionIndex sectionIndex: Int, sectionName: String) {
		switch changeType.rawValue {
			case NSFetchedResultsChangeType.insert.rawValue: currentSectionInserts.addSectionChange(name: sectionName, at: sectionIndex)
			case NSFetchedResultsChangeType.delete.rawValue: currentSectionDeletes.addSectionChange(name: sectionName, at: sectionIndex)
			case NSFetchedResultsChangeType.update.rawValue, NSFetchedResultsChangeType.move.rawValue:
				/* The update and move change type are invalid for a section change.
				 * We only do an assertion failure and not a fatal error because CoreData is capricious and I don’t trust it (see next case). */
				assertionFailure("Invalid change type \(changeType) for a section change.")
			default:
				/* We got an unknown section change type.
				 * We only do an assertion failure and not a fatal error to not crash in prod as an abundance of caution.
				 * For row changes we _can_ get invalid change type (see the addRowChange function). */
				assertionFailure("Unknown Core Data change type \(changeType) (section change).")
		}
	}
	
	public func addRowChange(_ changeType: NSFetchedResultsChangeType, atIndexPath srcIndexPath: IndexPath?, newIndexPath dstIndexPath: IndexPath?, for object: RowItemID) {
		/* Note: We do not uncomment the asserts below because NSFetchedResultsController is not safe and sometimes we can get values where none are expected.
		 * Known case is for the update, where from iOS 7.1 the update gets a destination index.
		 * See <http://stackoverflow.com/a/32213076>. */
		switch changeType.rawValue {
			case NSFetchedResultsChangeType.update.rawValue: currentStaticRowChanges.append(RowChangeInfo(change: .update(srcPath: .init(indexPath: srcIndexPath!)!), itemID: object)); //; assert(dstIndexPath == nil)
			case NSFetchedResultsChangeType.insert.rawValue: currentMovingRowChanges.append(RowChangeInfo(change: .insert(dstPath: .init(indexPath: dstIndexPath!)!), itemID: object)); //; assert(srcIndexPath == nil)
			case NSFetchedResultsChangeType.delete.rawValue: currentMovingRowChanges.append(RowChangeInfo(change: .delete(srcPath: .init(indexPath: srcIndexPath!)!), itemID: object)); //; assert(dstIndexPath == nil)
			case NSFetchedResultsChangeType.move.rawValue:
				let update1 = RowChangeInfo(change: .delete(srcPath: .init(indexPath: srcIndexPath!)!), itemID: object)
				let update2 = RowChangeInfo(change: .insert(dstPath: .init(indexPath: dstIndexPath!)!), itemID: object)
				update1.linkedChangeForMove = update2
				update2.linkedChangeForMove = update1
				currentMovingRowChanges.append(update1)
				currentMovingRowChanges.append(update2)
				
			default:
				/* In certain very rare cases Core Data sends invalid change types
				 *  (e.g. on iOS 8, w/ the app is compiled with Xcode 7, we can receive changes of type 0, which is invalid).
				 * For this reason with do a simple assertion failure here instead of a hard fatal error to avoid crashing in prod when it can be avoided. */
				assertionFailure("Unknown change type \(changeType).")
		}
	}
	
	public var isEmpty: Bool {
		currentSectionInserts.isEmpty && currentSectionDeletes.isEmpty &&
		currentStaticRowChanges.isEmpty && currentMovingRowChanges.isEmpty
	}
	
	public func removeAllChanges() {
		currentSectionInserts.removeAll()
		currentSectionDeletes.removeAll()
		currentStaticRowChanges.removeAll()
		currentMovingRowChanges.removeAll()
	}
	
	/* If you have an Array, you can simply update, delete, move and insert the items directly at the indices given by the handler and you will be good to go!
	 * For the moves, delete source, then insert at destination (in this order).
	 * Do NOT exchanges source and destination! */
	public func iterateAggregatedChanges(andClearChanges clearChanges: Bool = true, _ handler: (AggregatedCoreDataChange<RowItemID>) -> Void) {
		/* ********* Call the row updates. ********* */
		for change in currentStaticRowChanges {
			handler(.row(change.change, change.itemID))
		}
		
		/* ********* Compute the inserts/deletes deltas. ********* */
		var currentInsertDelta = 0
		var sectionInsertDeltas = [Int]()
		for (idx, insert) in currentSectionInserts.enumerated() {
			if let insert {
				handler(.section(.insert(dstIdx: idx), insert))
				let deltaIdx = idx - currentInsertDelta
				assert(deltaIdx >= 0)
				sectionInsertDeltas.extendForDeltas(minCount: deltaIdx + 1)
				currentInsertDelta += 1
				sectionInsertDeltas[deltaIdx] = currentInsertDelta
			}
		}
		var currentDeleteDelta = 0
		var sectionDeleteDeltas = [Int]()
		for (idx, delete) in currentSectionDeletes.enumerated() {
			if delete != nil {
				let idx = adjustSrcIdx(idx, withInsertDeltas: sectionInsertDeltas)
				let deltaIdx = idx - currentDeleteDelta
				assert(deltaIdx >= 0)
				sectionDeleteDeltas.extendForDeltas(minCount: deltaIdx + 1)
				currentDeleteDelta += 1
				sectionDeleteDeltas[deltaIdx] = currentDeleteDelta
			}
		}
		
		/* ********* Sort/reindex the row inserts, deletes and moves, and call them. ********* */
		currentMovingRowChanges.forEach{ $0.adjustSection(sectionInsertDeltas: sectionInsertDeltas, sectionDeleteDeltas: sectionDeleteDeltas) }
		currentMovingRowChanges.sort(by: { change1, change2 in
			assert(change1.isDelete || change1.isInsert)
			assert(change2.isDelete || change2.isInsert)
			
			if change1.isDelete && change2.isInsert {return true}
			if change1.isInsert && change2.isDelete {return false}
			
			if change1.isInsert {assert(change1.dstPath != change2.dstPath); return (change1.dstPath! < change2.dstPath!)}
			else                {assert(change1.srcPath != change2.srcPath); return (change1.srcPath! > change2.srcPath!)}
		})
		var i = 0, n = currentMovingRowChanges.count
		while i < n {
			let currentChange = currentMovingRowChanges[i]
			assert(currentChange.__idx == nil || currentChange.__idx == i, "INTERNAL ERROR: Invalid __idx.")
			currentChange.__idx = i
			
//			if #available(macOS 11.0, tvOS 14.0, iOS 14.0, watchOS 7.0, *) {
//				Logger.main.trace("-----")
//				Logger.main.trace("\(currentChange, privacy: .public)")
//				Logger.main.trace("----")
//			}
//			prettyPrintRowChanges(currentMovingRowChanges)
			if currentChange.isInsert, let linkedChange = currentChange.linkedChangeForMove, linkedChange.__idx != i-1 {
				assert(i > 0, "INTERNAL LOGIC ERROR")
				assert(currentChange.__idx == i, "INTERNAL LOGIC ERROR")
				assert(currentChange.__idx > linkedChange.__idx + 1, "INTERNAL ERROR")
				for j in stride(from: i, to: linkedChange.__idx + 1, by: -1) {
					assert(currentMovingRowChanges[j] === currentChange, "INTERNAL LOGIC ERROR")
					let swappedChange = currentMovingRowChanges[j-1]
					switch (currentChange.change, swappedChange.change) {
						case let (.insert(curDstPath), .insert(swpDstPath)):
							if curDstPath.secIdx == swpDstPath.secIdx {
								/* If both indices are in the same section, we have to tweak them. */
								if curDstPath <= swpDstPath {swappedChange.change = .insert(dstPath: swpDstPath.withRowDelta( 1))}
								else                        {currentChange.change = .insert(dstPath: curDstPath.withRowDelta(-1))}
							}
							
						case let (.delete(curSrcPath), .insert(swpDstPath)):
							if curSrcPath.secIdx == swpDstPath.secIdx {
								/* If both indices are in the same section, we have to tweak them. */
								if      curSrcPath > swpDstPath {currentChange.change = .delete(srcPath: curSrcPath.withRowDelta( 1))}
								else if curSrcPath < swpDstPath {swappedChange.change = .insert(dstPath: swpDstPath.withRowDelta(-1))}
								else {fatalError("Equality should not be possible here.")}
							}
							
						case let (.insert(curDstPath), .delete(swpSrcPath)):
							if curDstPath.secIdx == swpSrcPath.secIdx {
								/* If both indices are in the same section, we have to tweak them. */
								if swpSrcPath >= curDstPath {swappedChange.change = .delete(srcPath: swpSrcPath.withRowDelta(1))}
								else                        {currentChange.change = .insert(dstPath: curDstPath.withRowDelta(1))}
							}
							
						case let (.delete(curSrcPath), .delete(swpSrcPath)):
							if curSrcPath.secIdx == swpSrcPath.secIdx {
								/* If both indices are in the same section, we have to tweak them. */
								if      swpSrcPath < curSrcPath {currentChange.change = .delete(srcPath: curSrcPath.withRowDelta( 1))}
								else if swpSrcPath > curSrcPath {swappedChange.change = .delete(srcPath: swpSrcPath.withRowDelta(-1))}
								/* In case of equality, there’s nothing to do. */
							}
							
						default:
							assertionFailure("INTERNAL LOGIC ERROR")
					}
					currentMovingRowChanges.swapAt(j, j-1)
					currentMovingRowChanges[j].__idx = j
					currentMovingRowChanges[j-1].__idx = j-1
//					prettyPrintRowChanges(currentMovingRowChanges)
				}
			}
			i += 1
		}
		i = 0
		while i < n {
			let currentChange = currentMovingRowChanges[i]; i += 1
			if !currentChange.isNonAtomicMove {handler(.row(currentChange.change, currentChange.itemID))}
			else {
				assert(currentChange.linkedChangeForMove === currentMovingRowChanges[i], "INTERNAL LOGIC ERROR")
				let atomicChange = currentChange.atomicMoveUpdate
				handler(.row(atomicChange.change, atomicChange.itemID))
				i += 1
			}
		}
		
		/* ********* Call the section deletes. ********* */
		for (idx, delete) in currentSectionDeletes.enumerated().reversed() {
			guard let delete else {continue}
			handler(.section(.delete(srcIdx: adjustSrcIdx(idx, withInsertDeltas: sectionInsertDeltas)), delete))
		}
		
		/* ********* Finally, let’s remove all the registered changes as they are applied. ********* */
		if clearChanges {
			removeAllChanges()
		}
	}
	
	/* For both arrays, the value is the name of the section being inserted/deleted.
	 * If nil, there’s no change at this index. */
	private var currentSectionInserts = [String?]()
	private var currentSectionDeletes = [String?]()
	
	private var currentMovingRowChanges = [RowChangeInfo<RowItemID>]()
	private var currentStaticRowChanges = [RowChangeInfo<RowItemID>]()
	
	private func prettyPrintRowChanges(_ changes: [RowChangeInfo<RowItemID>]) {
		if #available(macOS 11.0, tvOS 14.0, iOS 14.0, watchOS 7.0, *) {
			Logger.main.trace("[\n\(changes.map{ "  \($0)" }.joined(separator: "\n"), privacy: .public)\n]")
		}
	}
	
}


private extension Array {
	
	subscript<T>(safe idx: Int) -> T? where Element == Optional<T> {
		get {
			assert(idx >= 0) /* Yes, the function is “safe,” but calling with an index lower than 0 is still illegal. */
			guard idx < endIndex else {return nil}
			return self[idx]
		}
		set {
			assert(idx >= 0) /* Yes, the function is “safe,” but calling with an index lower than 0 is still illegal. */
			ensureCount(idx + 1)
			self[idx] = newValue
		}
	}
	
	mutating func ensureCount<T>(_ minCount: Int) where Element == Optional<T> {
		assert(minCount >= 0)
		guard minCount > count else {return}
		append(contentsOf: [T?](repeating: nil, count: minCount - count))
	}
	
}


private extension Array where Element == Int {
	
	mutating func extendForDeltas(minCount: Int) {
		assert(minCount >= 0)
		guard minCount > count else {return}
		append(contentsOf: [Int](repeating: last ?? 0, count: minCount - count))
	}
	
}


private extension Array where Element == String? {
	
	mutating func addSectionChange(name: String, at idx: Int) {
		assert(self[safe: idx] == nil)
		self[safe: idx] = name
	}
	
}
