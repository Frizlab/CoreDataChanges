import Foundation



public enum AggregatedCoreDataChange<RowItemID> : CustomStringConvertible {
	
	case section(SectionChange, String) /* Note: The section ID is always a String when using an NSFetchedResultsController. */
	case row(RowChange, RowItemID)
	
	public var description: String {
		switch self {
			case let .section(change, _): return "section-\(change)"
			case let .row    (change, _): return     "row-\(change)"
		}
	}
	
}
