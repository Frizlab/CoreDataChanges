import enum CoreData.NSFetchedResultsChangeType
import Foundation



internal final class RowChangeInfo<RowItemID> : CustomStringConvertible {
	
	var change: RowChange
	let itemID: RowItemID
	
	weak var linkedChangeForMove: RowChangeInfo?
	var isNonAtomicMove: Bool {linkedChangeForMove != nil}
	
	/* Both are only used by the algorithm to aggregate the updates. */
	var __idx: Int!
	var __sectionAdjusted: Bool = false
	
	init(change: RowChange, itemID: RowItemID) {
		self.change = change
		self.itemID = itemID
		self.__idx = nil
	}
	
	func adjustSectionIfNeeded(sectionInsertDeltas: [Int], sectionDeleteDeltas: [Int]) {
		guard !__sectionAdjusted else {
			return
		}
		
		switch change {
			case let .update(srcPath): change = .update(srcPath: Self.adjustSrcPath(srcPath, withInsertDeltas: sectionInsertDeltas))
			case let .insert(dstPath): change = .insert(dstPath: Self.adjustDstPath(dstPath, withDeleteDeltas: sectionDeleteDeltas))
			case let .delete(srcPath): change = .delete(srcPath: Self.adjustSrcPath(srcPath, withInsertDeltas: sectionInsertDeltas))
			case let .move(srcPath, dstPath):
				change = .move(
					srcPath: Self.adjustSrcPath(srcPath, withInsertDeltas: sectionInsertDeltas),
					dstPath: Self.adjustDstPath(dstPath, withDeleteDeltas: sectionDeleteDeltas)
				)
		}
		__sectionAdjusted = true
	}
	
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
	
	static func adjustSrcPath(_ srcPath: RowPath, withInsertDeltas insertDeltas: [Int]) -> RowPath {
		return .init(secIdx: SectionInfo.adjustSrcIdx(srcPath.secIdx, withInsertDeltas: insertDeltas), rowIdx: srcPath.rowIdx)
	}
	
	static func adjustDstPath(_ dstPath: RowPath, withDeleteDeltas deleteDeltas: [Int]) -> RowPath {
		return .init(secIdx: SectionInfo.adjustDstIdx(dstPath.secIdx, withDeleteDeltas: deleteDeltas), rowIdx: dstPath.rowIdx)
	}
	
}
