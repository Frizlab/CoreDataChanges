import enum CoreData.NSFetchedResultsChangeType
import Foundation
import os.log



public final class CoreDataChangesAggregator<RowItemID> {
	
	public init() {
	}
	
	public func addSectionChange(_ changeType: NSFetchedResultsChangeType, atSectionIndex sectionIndex: Int, sectionName: String) {
//		switch changeType.rawValue {
//			case NSFetchedResultsChangeType.insert.rawValue:
//				/* Core Data guarantees the section changes are sent _before_ the row changes (says the doc).
//				 * We do not support aggregating multiple “waves” of changes:
//				 *  all and only the changes between the `controllerWillChangeContent` and `controllerDidChangeContent` method calls must be sent.
//				 * We could easily re-order the currentRowAggregators array when starting receiving new section changes,
//				 *  but we’d also have to add the support for multiple waves of changes in CoreDataSingleSectionChangesAggregator.
//				 * Currently (and probably forever) we do not need this capability.
//				 * If you needed later, there is a simpler solution anyway: create an aggregator per wave and iterate on the changes on each aggregator.
//				 * Note: The assert is only for insertion. For deletion, the rows in the sections are reported as deleted first, thus contradicting the doc. */
//				assert(currentRowAggregators.allSatisfy(\.isEmpty), "Adding section changes must not be done after row changes have been added. More info in the code.")
//				currentSectionChanges.append((SectionChange(cdType: changeType, index: sectionIndex), sectionName))
//				
//			case NSFetchedResultsChangeType.delete.rawValue:
//				/* We observed the rows in the deleted sections are reported deleted before the whole section is reported as deleted.
//				 * If we have row changes for the deleted section (we should have all the rows in the section reported deleted), we remove these reports. */
//				if sectionIndex < currentRowAggregators.count {
//					assert(currentRowAggregators[sectionIndex].hasOnlyDeletions)
//					currentRowAggregators[sectionIndex].removeAllChanges()
//				} else {
//					Logger.coreData.notice("Expected rows to have been reported as deleted before the section was reported deleted, but I do not have a row aggregator for deleted section at index \(sectionIndex) (\(sectionName, privacy: .public)). Was the section emtpy? I might also have misunderstood CoreData; would not be the first time…")
//				}
//				currentSectionChanges.append((SectionChange(cdType: changeType, index: sectionIndex), sectionName))
//				
//			case NSFetchedResultsChangeType.update.rawValue, NSFetchedResultsChangeType.move.rawValue:
//				/* The update and move change type are invalid for a section change.
//				 * We only do an assertion failure and not a fatal error because CoreData is capricious and I don’t trust it (see next case). */
//				assertionFailure("Invalid change type \(changeType) for a section change.")
//				
//			default:
//				/* We got an unknown section change type.
//				 * We only do an assertion failure and not a fatal error to not crash in prod as an abundance of caution.
//				 * For row changes we _can_ get invalid change type (see the addRowChange function). */
//				assertionFailure("Unknown Core Data change type \(changeType) (section change).")
//		}
	}
	
	public func addRowChange(_ changeType: NSFetchedResultsChangeType, atIndexPath srcIndexPath: IndexPath?, newIndexPath dstIndexPath: IndexPath?, for object: RowItemID) {
		/* Note: We do not uncomment the asserts below because NSFetchedResultsController is not safe and sometimes we can get values where none are expected.
		 * Known case is for the update, where from iOS 7.1 the update gets a destination index.
		 * See <http://stackoverflow.com/a/32213076>. */
		switch changeType.rawValue {
			case NSFetchedResultsChangeType.update.rawValue: currentStaticChanges.append(RowChangeInfo(change: .update(srcPath: .init(indexPath: srcIndexPath!)!), itemID: object)); //; assert(dstIndexPath == nil)
			case NSFetchedResultsChangeType.insert.rawValue: currentMovingChanges.append(RowChangeInfo(change: .insert(dstPath: .init(indexPath: dstIndexPath!)!), itemID: object)); //; assert(srcIndexPath == nil)
			case NSFetchedResultsChangeType.delete.rawValue: currentMovingChanges.append(RowChangeInfo(change: .delete(srcPath: .init(indexPath: srcIndexPath!)!), itemID: object)); //; assert(dstIndexPath == nil)
			case NSFetchedResultsChangeType.move.rawValue:
				let update1 = RowChangeInfo(change: .delete(srcPath: .init(indexPath: srcIndexPath!)!), itemID: object)
				let update2 = RowChangeInfo(change: .insert(dstPath: .init(indexPath: dstIndexPath!)!), itemID: object)
				update1.linkedChangeForMove = update2
				update2.linkedChangeForMove = update1
				currentMovingChanges.append(update1)
				currentMovingChanges.append(update2)
				
			default:
				/* In certain very rare cases Core Data sends invalid change types
				 *  (e.g. on iOS 8, w/ the app is compiled with Xcode 7, we can receive changes of type 0, which is invalid).
				 * For this reason with do a simple assertion failure here instead of a hard fatal error to avoid crashing in prod when it can be avoided. */
				assertionFailure("Unknown change type \(changeType).")
		}
	}
	
	public var isEmpty: Bool {
		(currentStaticChanges.isEmpty && currentMovingChanges.isEmpty)
	}
	
	public func removeAllChanges() {
		currentStaticChanges.removeAll()
		currentMovingChanges.removeAll()
	}
	
	/* If you have an Array, you can simply update, delete, move and insert the items directly at the indices given by the handler and you will be good to go!
	 * For the moves, delete source, then insert at destination (in this order).
	 * Do NOT exchanges source and destination! */
	public func iterateAggregatedChanges(andClearChanges clearChanges: Bool = true, _ handler: (AggregatedCoreDataChange<RowItemID>) -> Void) {
		/* ********* Let’s call the updates. ********* */
		for change in currentStaticChanges {
			handler(.row(change.change, change.itemID))
		}
		
		/* ********* Let’s sort/reindex the inserts, deletes and moves. ********* */
		currentMovingChanges.sort(by: { change1, change2 in
			assert(change1.isDelete || change1.isInsert)
			assert(change2.isDelete || change2.isInsert)
			
			if change1.isDelete && change2.isInsert {return true}
			if change1.isInsert && change2.isDelete {return false}
			
			if change1.isInsert {assert(change1.dstPath != change2.dstPath); return (change1.dstPath! < change2.dstPath!)}
			else                {assert(change1.srcPath != change2.srcPath); return (change1.srcPath! > change2.srcPath!)}
		})
		var i = 0, n = currentMovingChanges.count
		while i < n {
			let currentChange = currentMovingChanges[i]
			assert(currentChange.__idx == nil || currentChange.__idx == i, "INTERNAL ERROR: Invalid __idx.")
			currentChange.__idx = i
			
			if currentChange.isInsert, let linkedChange = currentChange.linkedChangeForMove, linkedChange.__idx != i-1 {
				assert(i > 0, "INTERNAL LOGIC ERROR")
				assert(currentChange.__idx == i, "INTERNAL LOGIC ERROR")
				assert(currentChange.__idx > linkedChange.__idx + 1, "INTERNAL ERROR")
				for j in stride(from: i, to: linkedChange.__idx + 1, by: -1) {
					assert(currentMovingChanges[j] === currentChange, "INTERNAL LOGIC ERROR")
					let swappedChange = currentMovingChanges[j-1]
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
					currentMovingChanges.swapAt(j, j-1)
				}
			}
			i += 1
		}
		i = 0
		while i < n {
			let currentChange = currentMovingChanges[i]; i += 1
			if !currentChange.isNonAtomicMove {handler(.row(currentChange.change, currentChange.itemID))}
			else {
				assert(currentChange.linkedChangeForMove === currentMovingChanges[i], "INTERNAL LOGIC ERROR")
				let atomicChange = currentChange.atomicMoveUpdate
				handler(.row(atomicChange.change, atomicChange.itemID))
				i += 1
			}
		}
		
		/* ********* Finally, let’s remove all the registered changes as they are applied. ********* */
		if clearChanges {
			removeAllChanges()
		}
	}
	
	private var currentMovingChanges = [RowChangeInfo<RowItemID>]()
	private var currentStaticChanges = [RowChangeInfo<RowItemID>]()
	
}
