import CoreData
import Foundation



extension NSFetchedResultsChangeType : CustomStringConvertible {
	
	public var description: String {
		switch self {
			case .delete: return "delete"
			case .insert: return "insert"
			case .move:   return "move"
			case .update: return "update"
			@unknown default: return "huh?"
		}
	}
	
}
