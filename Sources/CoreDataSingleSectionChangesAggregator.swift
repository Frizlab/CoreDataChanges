import enum CoreData.NSFetchedResultsChangeType
import Foundation
import UIKit



public enum AggregatedSingleSectionCoreDataChange : Hashable, CustomStringConvertible {
	
	case update(srcIdx: Int) /* An update *can* have a destination index, but we have deemed it useless for our use case. */
	case insert(dstIdx: Int)
	case delete(srcIdx: Int)
	case move(srcIdx: Int, dstIdx: Int)
	
	public var description: String {
		switch self {
			case let .update(srcIdx): return "update(\(srcIdx))"
			case let .insert(dstIdx): return "insert(\(dstIdx))"
			case let .delete(srcIdx): return "delete(\(srcIdx))"
			case let .move(srcIdx, dstIdx): return "move(\(srcIdx), \(dstIdx))"
		}
	}
	
}


public final class CoreDataSingleSectionChangesAggregator<Element> {
	
	public init() {
	}
	
	public func addChange(_ changeType: NSFetchedResultsChangeType, atIndexPath srcIndexPath: IndexPath?, newIndexPath dstIndexPath: IndexPath?, for object: Element) {
		assert(srcIndexPath == nil || dstIndexPath == nil || srcIndexPath?.section == dstIndexPath?.section)
		assert(section == nil || (dstIndexPath?.section ?? section) == section)
		assert(section == nil || (srcIndexPath?.section ?? section) == section)
		section = (srcIndexPath?.section ?? dstIndexPath?.section)!
		switch changeType.rawValue {
			case NSFetchedResultsChangeType.update.rawValue: currentStaticChanges.append(Change(cdType: changeType, srcIndexPath: srcIndexPath, dstIndexPath: dstIndexPath, object: object))
			case NSFetchedResultsChangeType.insert.rawValue: currentMovingChanges.append(Change(cdType: changeType, srcIndexPath: srcIndexPath, dstIndexPath: dstIndexPath, object: object))
			case NSFetchedResultsChangeType.delete.rawValue: currentMovingChanges.append(Change(cdType: changeType, srcIndexPath: srcIndexPath, dstIndexPath: dstIndexPath, object: object))
			case NSFetchedResultsChangeType.move.rawValue:
				let update1 = Change(cdType: .delete, srcIndexPath: srcIndexPath, dstIndexPath: nil,          object: object)
				let update2 = Change(cdType: .insert, srcIndexPath: nil,          dstIndexPath: dstIndexPath, object: object)
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
	
	public var hasOnlyDeletions: Bool {
		return currentStaticChanges.isEmpty && currentMovingChanges.allSatisfy(\.isDelete)
	}
	
	public func removeAllChanges() {
		currentStaticChanges.removeAll()
		currentMovingChanges.removeAll()
		section = nil
	}
	
	/* If you have an NSMutableArray, you can simply update, delete, move and insert the elements directly at the indexes given by the handler and you will be good to go!
	 * For the moves, delete source, then insert at destination (in this order).
	 * Do NOT exchanges source and destination! */
	public func iterateAggregatedChanges(andClearChanges clearChanges: Bool = true, _ handler: (AggregatedSingleSectionCoreDataChange, Element) -> Void) {
		/* ********* Let’s call the updates. ********* */
		for change in currentStaticChanges {
			handler(change.change, change.item)
		}
		
		/* ********* Let’s sort/reindex the inserts, deletes and moves. ********* */
		currentMovingChanges.sort(by: { change1, change2 in
			assert(change1.isDelete || change1.isInsert)
			assert(change2.isDelete || change2.isInsert)
			
			if change1.isDelete && change2.isInsert {return true}
			if change1.isInsert && change2.isDelete {return false}
			
			if change1.isInsert {assert(change1.dstIndex != change2.dstIndex); return (change1.dstIndex! < change2.dstIndex!)}
			else                {assert(change1.srcIndex != change2.srcIndex); return (change1.srcIndex! > change2.srcIndex!)}
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
						case let (.insert(curDstIdx), .insert(swpDstIdx)):
							if curDstIdx <= swpDstIdx {
								swappedChange.change = .insert(dstIdx: swpDstIdx + 1)
							} else {
								assert(curDstIdx > 0, "INTERNAL LOGIC ERROR")
								currentChange.change = .insert(dstIdx: curDstIdx - 1)
							}
							
						case let (.delete(curSrcIdx), .insert(swpDstIdx)):
							if curSrcIdx > swpDstIdx {
								currentChange.change = .delete(srcIdx: curSrcIdx + 1)
							} else {
								assert(swpDstIdx > 0, "INTERNAL LOGIC ERROR")
								assert(curSrcIdx < swpDstIdx, "INTERNAL LOGIC ERROR") /* Equality case is not possible. */
								swappedChange.change = .insert(dstIdx: swpDstIdx - 1)
							}
							
						case let (.insert(curDstIdx), .delete(swpSrcIdx)):
							if swpSrcIdx >= curDstIdx {swappedChange.change = .delete(srcIdx: swpSrcIdx + 1)}
							else                      {currentChange.change = .insert(dstIdx: curDstIdx + 1)}
							
						case let (.delete(curSrcIdx), .delete(swpSrcIdx)):
							if      swpSrcIdx < curSrcIdx {currentChange.change = .delete(srcIdx: curSrcIdx + 1)}
							else if swpSrcIdx > curSrcIdx {
								assert(swpSrcIdx > 0, "INTERNAL LOGIC ERROR")
								swappedChange.change = .delete(srcIdx: swpSrcIdx - 1)
							}
							/* In case of equality, there’s nothing to do. */
							
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
			if !currentChange.isNonAtomicMove {handler(currentChange.change, currentChange.item)}
			else {
				assert(currentChange.linkedChangeForMove === currentMovingChanges[i], "INTERNAL LOGIC ERROR")
				let atomicChange = currentChange.atomicMoveUpdate
				handler(atomicChange.change, atomicChange.item)
				i += 1
			}
		}
		
		/* ********* Finally, let’s remove all the registered changes as they are applied. ********* */
		if clearChanges {
			removeAllChanges()
		}
	}
	
	private final class Change : CustomStringConvertible {
		
		convenience init(cdType: NSFetchedResultsChangeType, srcIndexPath: IndexPath?, dstIndexPath: IndexPath?, object: Element) {
			assert(srcIndexPath == nil || dstIndexPath == nil || srcIndexPath?.section == dstIndexPath?.section)
			self.init(cdType: cdType, srcIndex: srcIndexPath?.item, dstIndex: dstIndexPath?.item, object: object)
		}
		
		init(cdType: NSFetchedResultsChangeType, srcIndex: Int?, dstIndex: Int?, object: Element) {
			/* Note: We do not uncomment the asserts below because NSFetchedResultsController is not safe and sometimes we can get values where none are expected.
			 * Known case is for the update, where from iOS 7.1 the update gets a destination index.
			 * See <http://stackoverflow.com/a/32213076>. */
			switch cdType {
				case .update: self.change = .update(srcIdx: srcIndex!)//; assert(dstIndex == nil)
				case .insert: self.change = .insert(dstIdx: dstIndex!)//; assert(srcIndex == nil)
				case .delete: self.change = .delete(srcIdx: srcIndex!)//; assert(dstIndex == nil)
				case .move:   self.change = .move(srcIdx: srcIndex!, dstIdx: dstIndex!)
				@unknown default:
					/* We can afford a fatal error as we only init a Change w/ known change types. */
					fatalError("Unknown change type \(cdType).")
			}
			self.__idx = nil
			self.item = object
		}
		
		let item: Element
		var change: AggregatedSingleSectionCoreDataChange
		
		weak var linkedChangeForMove: Change?
		var isNonAtomicMove: Bool {linkedChangeForMove != nil}
		
		/* Only used by the algorithm to aggregate the updates. */
		var __idx: Int!
		
		var isInsert: Bool {
			switch change {
				case .insert:                 return true
				case .update, .delete, .move: return false
			}
		}
		
		var isDelete: Bool {
			switch change {
				case .delete:                 return true
				case .update, .insert, .move: return false
			}
		}
		
		var srcIndex: Int? {
			switch change {
				case let .delete(srcIdx), let .update(srcIdx), let .move(srcIdx, _): return srcIdx
				case .insert:                                                        return nil
			}
		}
		
		var dstIndex: Int? {
			switch change {
				case let .insert(dstIdx), let .move(_, dstIdx): return dstIdx
				case .delete, .update:                          return nil
			}
		}
		
		var atomicMoveUpdate: Change {
			let linkedChangeForMove = linkedChangeForMove!
			assert(linkedChangeForMove.linkedChangeForMove! === self, "I’m invalid (linked update of linked update is not me): \(self)")
//			assert(item === linkedChangeForMove.item, "I’m invalid (linked object != my object): \(self) - \(linkedChangeForMove)")
			let delete = (isDelete ? self : linkedChangeForMove)
			let insert = (isInsert ? self : linkedChangeForMove)
			assert(delete.isDelete, "I’m invalid (delete is not delete): \(self) - \(delete)")
			assert(insert.isInsert, "I’m invalid (insert is not insert): \(self) - \(insert)")
			return Self(cdType: .move, srcIndex: delete.srcIndex, dstIndex: insert.dstIndex, object: insert.item)
		}
		
		var description: String {
			return "CoreDataSingleSectionChangesAggregator.Change<\(Unmanaged.passUnretained(self).toOpaque())>.\(change) --> \(String(describing: linkedChangeForMove.flatMap{ Unmanaged.passUnretained($0).toOpaque() }))"
		}
		
	}
	
	private var section: Int? /* Only for asserting we’re only getting updates from the same section. */
	private var currentMovingChanges = [Change]()
	private var currentStaticChanges = [Change]()
	
}
