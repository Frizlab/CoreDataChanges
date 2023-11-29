import Foundation



public enum SectionChange : CustomStringConvertible {
	
	case insert(dstIdx: Int)
	case delete(srcIdx: Int)
	
	public var description: String {
		switch self {
			case let .insert(dstIdx): return "insert(\(dstIdx))"
			case let .delete(srcIdx): return "delete(\(srcIdx))"
		}
	}
	
}
