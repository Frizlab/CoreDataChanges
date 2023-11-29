import enum CoreData.NSFetchedResultsChangeType
import Foundation



internal final class RowChangeInfo<RowItemID> : CustomStringConvertible {
	
	var change: RowChange
	let itemID: RowItemID
	
	weak var linkedChangeForMove: RowChangeInfo?
	var isNonAtomicMove: Bool {linkedChangeForMove != nil}
	
	/* Only used by the algorithm to aggregate the updates. */
	var __idx: Int!
	
	init(change: RowChange, itemID: RowItemID) {
		self.change = change
		self.itemID = itemID
		self.__idx = nil
	}
//	init(cdType: NSFetchedResultsChangeType, srcPath: RowPath?, dstPath: RowPath?, itemID: RowItemID) {
		/* Note: We do not uncomment the asserts below because NSFetchedResultsController is not safe and sometimes we can get values where none are expected.
		 * Known case is for the update, where from iOS 7.1 the update gets a destination index.
		 * See <http://stackoverflow.com/a/32213076>. */
//		switch cdType {
//			case .update: self.change = .update(srcPath: srcPath!)//; assert(dstPath == nil)
//			case .insert: self.change = .insert(dstPath: dstPath!)//; assert(srcPath == nil)
//			case .delete: self.change = .delete(srcPath: srcPath!)//; assert(dstPath == nil)
//			case .move:   self.change = .move(srcPath: srcPath!, dstPath: dstPath!)
//			@unknown default:
//				/* We can afford a fatal error as we only init a Change w/ known change types. */
//				fatalError("Unknown change type \(cdType).")
//		}
//		self.__idx = nil
//		self.itemID = itemID
//	}
	
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
	
	var srcPath: RowPath? {
		switch change {
			case let .delete(srcPath), let .update(srcPath), let .move(srcPath, _): return srcPath
			case .insert:                                                           return nil
		}
	}
	
	var dstPath: RowPath? {
		switch change {
			case let .insert(dstPath), let .move(_, dstPath): return dstPath
			case .delete, .update:                            return nil
		}
	}
	
	var atomicMoveUpdate: RowChangeInfo {
		let linkedChangeForMove = linkedChangeForMove!
		assert(linkedChangeForMove.linkedChangeForMove! === self, "I’m invalid (linked update of linked update is not me): \(self)")
//		assert(item === linkedChangeForMove.item, "I’m invalid (linked object != my object): \(self) - \(linkedChangeForMove)")
		let delete = (isDelete ? self : linkedChangeForMove)
		let insert = (isInsert ? self : linkedChangeForMove)
		assert(delete.isDelete, "I’m invalid (delete is not delete): \(self) - \(delete)")
		assert(insert.isInsert, "I’m invalid (insert is not insert): \(self) - \(insert)")
		return RowChangeInfo(change: .move(srcPath: delete.srcPath!, dstPath: insert.dstPath!), itemID: insert.itemID)
	}
	
	var description: String {
		return "RowChangeInfo<\(Unmanaged.passUnretained(self).toOpaque())>.\(change) --> \(String(describing: linkedChangeForMove.flatMap{ Unmanaged.passUnretained($0).toOpaque() }))"
	}
	
}
