import CoreData
import Foundation
import XCTest

@testable import CoreDataChanges



final class RealCoreDataChangesAggregatorTests : XCTestCase {
	
	var context: NSManagedObjectContext!
	
	override func setUp() async throws {
		let model = NSManagedObjectModel()
		model.entities = [
			{
				let entity = NSEntityDescription()
				entity.name = "Entity"
				entity.managedObjectClassName = "Entity"
				entity.properties = [
					{
						let property = NSAttributeDescription()
						property.name = "title"
						property.attributeType = .stringAttributeType
						return property
					}(),
					{
						let property = NSAttributeDescription()
						property.name = "section"
						property.attributeType = .stringAttributeType
						return property
					}(),
				]
				return entity
			}(),
		]
		let persistentCoordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
		_ = try persistentCoordinator.addPersistentStore(type: .inMemory, at: URL(fileURLWithPath: "/dev/null"))
		context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
		context.persistentStoreCoordinator = persistentCoordinator
	}
	
	override func tearDown() async throws {
		context = nil
	}
	
	func testSetup() throws {
		/* A dummy test that prints when going in the NSFetchedResultsControllerDelegate methods; just to verify our setup is correct. */
		let frc = createFRC()
		try printMonitor.startMonitor(controller: frc, context: context)
		
		wentInDidChangeOfPrintMonitor = false
		let entity = Entity(context: context)
		entity.title = "Yolo"
		entity.section = "y"
		context.processPendingChanges()
		XCTAssertTrue(wentInDidChangeOfPrintMonitor)
	}
	
	func testSimpleSingleSectionChange() throws {
		let section = "none"
		let entity1 = Entity(context: context, title: "1", section: section)
		let entity2 = Entity(context: context, title: "2", section: section)
		let entity3 = Entity(context: context, title: "3", section: section)
		let entity4 = Entity(context: context, title: "4", section: section)
		let entity5 = Entity(context: context, title: "5", section: section)
		context.processPendingChanges()
		
		let output = Ref([
			Section(name: "none", contents: [entity1.objectID, entity2.objectID, entity3.objectID, entity4.objectID, entity5.objectID])
		])
		let monitor = aggregatorMonitor(for: .init(), output: output)

		let frc = createFRC()
		try monitor.startMonitor(controller: frc, context: context)
		
		_ = Entity(context: context, title: "6", section: section)
		context.processPendingChanges()
		
		entity2.title = "7"
		context.delete(entity1)
		context.processPendingChanges()
		
		XCTAssertEqual(output.value, sections(from: frc))
	}
	
	func testFirstSectionCreation() throws {
		let section = "none"
		let output: Ref<[Section]> = .init([])
		let monitor = aggregatorMonitor(for: .init(), output: output)
		
		let frc = createFRC()
		try monitor.startMonitor(controller: frc, context: context)
		
		_ = Entity(context: context, title: "1", section: section)
		context.processPendingChanges()
		
		XCTAssertEqual(output.value, sections(from: frc))
	}
	
	private func sections(from frc: NSFetchedResultsController<Entity>) -> [Section] {
		return frc.sections!.map{ section in Section(name: section.name, contents: (section.objects as! [Entity]).map(\.objectID)) }
	}
	
	private func createFRC() -> NSFetchedResultsController<Entity> {
		let fRequest = Entity.fetchRequest() as! NSFetchRequest<Entity>
		fRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Entity.title, ascending: true)]
		return NSFetchedResultsController(fetchRequest: fRequest, managedObjectContext: context, sectionNameKeyPath: "section", cacheName: nil)
	}
	
	private var wentInDidChangeOfPrintMonitor: Bool = false
	private lazy var printMonitor = {
		CoreDataChangesMonitor(
			willChangeBlock:       {                                               print("will change") },
			didChangeSectionBlock: { type, sectionIndex, sectionInfo            in print("did change section \(sectionIndex), type \(type)") },
			didChangeRowBlock:     { type, srcIndexPath, newIndexPath, anObject in print("did change row at source \(srcIndexPath.flatMap{ "{\($0[0]),\($0[1])}" } ?? "<empty>"), destination \(newIndexPath.flatMap{ "{\($0[0]),\($0[1])}" } ?? "<empty>"), type \(type)") },
			didChangeBlock:        { [weak self] in                                print("did change"); self?.wentInDidChangeOfPrintMonitor = true }
		)
	}()
	
	private func aggregatorMonitor(for aggregator: CoreDataChangesAggregator<NSManagedObjectID>, output: Ref<[Section]>) -> CoreDataChangesMonitor {
		.init(
			willChangeBlock:       {                                               assert(aggregator.isEmpty) },
			didChangeSectionBlock: { type, sectionIndex, sectionInfo            in aggregator.addSectionChange(type, atSectionIndex: sectionIndex, sectionName: sectionInfo.name) },
			didChangeRowBlock:     { type, srcIndexPath, newIndexPath, anObject in aggregator.addRowChange(type, atIndexPath: srcIndexPath, newIndexPath: newIndexPath, for: (anObject as! NSManagedObject).objectID) },
			didChangeBlock:        {                                               aggregator.iterateAggregatedChanges{ change in
				switch change {
					case let .section(.insert(dstIdx), name):                                            output.value.insert(Section(name: name), at: dstIdx)
					case let .section(.delete(srcIdx), name): assert(output.value[srcIdx].name == name); output.value.remove(at: srcIdx)
						
					case let .row(.insert(dstPath), id):                                                                      output.value[dstPath.secIdx].contents.insert(id, at: dstPath.rowIdx)
					case let .row(.delete(srcPath), id): assert(output.value[srcPath.secIdx].contents[srcPath.rowIdx] == id); output.value[srcPath.secIdx].contents.remove(at: srcPath.rowIdx)
					case let .row(.update(srcPath), id): assert(output.value[srcPath.secIdx].contents[srcPath.rowIdx] == id)
					case let .row(.move(srcPath, dstPath), id):
						assert(output.value[srcPath.secIdx].contents[srcPath.rowIdx] == id)
						output.value[srcPath.secIdx].contents.remove(at: srcPath.rowIdx)
						output.value[dstPath.secIdx].contents.insert(id, at: dstPath.rowIdx)
				}
			} }
		)
	}
	
	private struct Section : Equatable, Hashable {
		
		var name: String
		var contents: [NSManagedObjectID] = []
		
	}
	
}


@objc(Entity)
final class Entity : NSManagedObject {
	
	@NSManaged var title: String?
	@NSManaged var section: String?
	
	convenience init(context: NSManagedObjectContext, title: String, section: String) {
		self.init(context: context)
		self.title = title
		self.section = section
	}
	
}
