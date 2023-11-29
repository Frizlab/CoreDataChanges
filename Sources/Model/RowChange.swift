import Foundation



public enum RowChange : CustomStringConvertible {
	
	case update(srcPath: RowPath) /* An update *can* have a destination index, but we have deemed it useless for our use case. */
	case insert(dstPath: RowPath)
	case delete(srcPath: RowPath)
	case move(srcPath: RowPath, dstPath: RowPath)
	
	public var description: String {
		switch self {
			case let .update(srcPath): return "update(\(srcPath))"
			case let .insert(dstPath): return "insert(\(dstPath))"
			case let .delete(srcPath): return "delete(\(srcPath))"
			case let .move(srcPath, dstPath): return "move(\(srcPath), \(dstPath))"
		}
	}
	
}
