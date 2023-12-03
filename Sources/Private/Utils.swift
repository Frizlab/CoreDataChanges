import Foundation



internal func adjustSrcPath(_ srcPath: RowPath, withInsertDeltas insertDeltas: [Int]) -> RowPath {
	return .init(secIdx: adjustSrcIdx(srcPath.secIdx, withInsertDeltas: insertDeltas), rowIdx: srcPath.rowIdx)
}

internal func adjustDstPath(_ dstPath: RowPath, withDeleteDeltas deleteDeltas: [Int]) -> RowPath {
	return .init(secIdx: adjustDstIdx(dstPath.secIdx, withDeleteDeltas: deleteDeltas), rowIdx: dstPath.rowIdx)
}

internal func adjustSrcIdx(_ srcIdx: Int, withInsertDeltas insertDeltas: [Int]) -> Int {
	return srcIdx + insertDeltas[forSectionDeltaAt: srcIdx]
}

internal func adjustDstIdx(_ dstIdx: Int, withDeleteDeltas deleteDeltas: [Int]) -> Int {
	return dstIdx + deleteDeltas[forSectionDeltaAt: dstIdx]
}


private extension Array where Element == Int {
	
	subscript(forSectionDeltaAt idx: Int) -> Int {
		guard !isEmpty else {return 0}
		return self[Swift.max(0, Swift.min(count - 1, idx))]
	}
	
}
