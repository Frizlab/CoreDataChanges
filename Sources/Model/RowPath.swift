import Foundation



public struct RowPath : Equatable, Hashable, Comparable, CustomStringConvertible {
	
	/* sec: it’s section, but w/ the same number of char than in row… */
	public var secIdx: Int {
		didSet {assert(secIdx >= 0)}
	}
	public var rowIdx: Int {
		didSet {assert(rowIdx >= 0)}
	}
	
	public init(secIdx: Int, rowIdx: Int) {
		assert(secIdx >= 0 && rowIdx >= 0)
		self.secIdx = secIdx
		self.rowIdx = rowIdx
	}
	
	public init?(indexPath: IndexPath) {
		guard indexPath.count == 2 else {
			return nil
		}
		
		/* Note: We cannot use section and row properties of IndexPath as we do not import UIKit. */
		self.secIdx = indexPath[0]
		self.rowIdx = indexPath[1]
		/* Let’s verify the input was valid. */
		guard secIdx >= 0 && rowIdx >= 0 else {
			return nil
		}
	}
	
	public func withRowDelta(_ delta: Int) -> RowPath {
		var ret = self
		ret.rowIdx += delta
		return ret
	}
	
	public var description: String {
		return "\(secIdx):\(rowIdx)"
	}
	
	public static func <(lhs: RowPath, rhs: RowPath) -> Bool {
		return (
			lhs.secIdx < rhs.secIdx || (
				lhs.secIdx == rhs.secIdx && lhs.rowIdx < rhs.rowIdx
			)
		)
	}
	
}
