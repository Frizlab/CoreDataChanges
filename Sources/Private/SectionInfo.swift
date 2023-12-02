import enum CoreData.NSFetchedResultsChangeType
import Foundation



internal final class SectionInfo : CustomStringConvertible {
	
	var idx: Int
	let name: String
	
	init(idx: Int, name: String) {
		self.idx = idx
		self.name = name
	}
	
	var description: String {
		return "SectionInfo<\(Unmanaged.passUnretained(self).toOpaque())>.idx(\(idx))"
	}
	
	static func adjustSrcIdx(_ srcIdx: Int, withInsertDeltas insertDeltas: [Int]) -> Int {
		return srcIdx + insertDeltas[forSectionDeltaAt: srcIdx]
	}
	
	static func adjustDstIdx(_ dstIdx: Int, withDeleteDeltas deleteDeltas: [Int]) -> Int {
		return dstIdx + deleteDeltas[forSectionDeltaAt: dstIdx]
	}
	
}


private extension Array where Element == Int {
	
	subscript(forSectionDeltaAt idx: Int) -> Int {
		guard !isEmpty else {return 0}
		return self[Swift.max(0, Swift.min(count - 1, idx))]
	}
	
}
