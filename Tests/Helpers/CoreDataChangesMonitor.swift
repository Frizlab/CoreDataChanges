import CoreData
import Foundation



class CoreDataChangesMonitor : NSObject, NSFetchedResultsControllerDelegate {
	
	var willChangeBlock: () -> Void
	var didChangeSectionBlock: (_ type: NSFetchedResultsChangeType, _ sectionIndex: Int, _ sectionInfo: NSFetchedResultsSectionInfo) -> Void
	var didChangeRowBlock: (_ type: NSFetchedResultsChangeType, _ srcIndexPath: IndexPath?, _ newIndexPath: IndexPath?, _ anObject: Any) -> Void
	var didChangeBlock: () -> Void
	
	init(
		willChangeBlock: @escaping () -> Void,
		didChangeSectionBlock: @escaping (_ type: NSFetchedResultsChangeType, _ sectionIndex: Int, _ sectionInfo: NSFetchedResultsSectionInfo) -> Void,
		didChangeRowBlock: @escaping (_ type: NSFetchedResultsChangeType, _ srcIndexPath: IndexPath?, _ newIndexPath: IndexPath?, _ anObject: Any) -> Void,
		didChangeBlock: @escaping () -> Void
	) {
		self.willChangeBlock = willChangeBlock
		self.didChangeSectionBlock = didChangeSectionBlock
		self.didChangeRowBlock = didChangeRowBlock
		self.didChangeBlock = didChangeBlock
		super.init()
	}
	
	deinit {
		stopMonitor()
	}
	
	func startMonitor<Result : NSFetchRequestResult>(controller: NSFetchedResultsController<Result>, context: NSManagedObjectContext) throws {
		assert(iAmUsingMe == nil && self.controller == nil)
		
		try controller.performFetch()
		
		self.controller = (controller as! NSFetchedResultsController<NSFetchRequestResult>)
		controller.delegate = self
		iAmUsingMe = self
	}
	
	func stopMonitor() {
		controller?.delegate = nil
		controller = nil
		iAmUsingMe = nil
	}
	
	func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		willChangeBlock()
	}
	
	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
		didChangeSectionBlock(type, sectionIndex, sectionInfo)
	}
	
	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
		didChangeRowBlock(type, indexPath, newIndexPath, anObject)
	}
	
	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		didChangeBlock()
	}
	
	private var controller: NSFetchedResultsController<NSFetchRequestResult>?
	private var iAmUsingMe: CoreDataChangesMonitor?
	
}
