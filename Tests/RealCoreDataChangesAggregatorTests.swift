import CoreData
import Foundation
import XCTest

@testable import CoreDataChanges



final class RealCoreDataChangesAggregatorTests : XCTestCase {
	
	var context: NSManagedObjectContext!
	
	static let model: NSManagedObjectModel = {
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
		return model
	}()
	
	override func setUpWithError() throws {
		let persistentCoordinator = NSPersistentStoreCoordinator(managedObjectModel: Self.model)
		_ = try persistentCoordinator.addPersistentStore(type: .inMemory, at: URL(fileURLWithPath: "/dev/null"))
		context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
		context.persistentStoreCoordinator = persistentCoordinator
	}
	
	override func tearDown() {
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
	
	func testLastSectionDeletion() throws {
		let section = "none"
		let entity1 = Entity(context: context, title: "1", section: section)
		context.processPendingChanges()
		
		let output = Ref([
			Section(name: "none", contents: [entity1.objectID])
		])
		let monitor = aggregatorMonitor(for: .init(), output: output)
		
		let frc = createFRC()
		try monitor.startMonitor(controller: frc, context: context)
		
		context.delete(entity1)
		context.processPendingChanges()
		
		XCTAssertEqual(output.value, sections(from: frc))
	}
	
	func testChangesOnSecondSection() throws {
		let section1 = "1"
		let section2 = "2"
		let e1s1 = Entity(context: context, title: "1-1", section: section1)
		let e1s2 = Entity(context: context, title: "2-1", section: section2)
		let e2s2 = Entity(context: context, title: "2-2", section: section2)
		let e3s2 = Entity(context: context, title: "2-3", section: section2)
		context.processPendingChanges()
		
		let output = Ref([
			Section(name: "1", contents: [e1s1.objectID]),
			Section(name: "2", contents: [e1s2.objectID, e2s2.objectID, e3s2.objectID]),
		])
		let monitor = aggregatorMonitor(for: .init(), output: output)
		
		let frc = createFRC()
		try monitor.startMonitor(controller: frc, context: context)
		
		context.delete(e2s2)
		context.processPendingChanges()
		
		XCTAssertEqual(output.value, sections(from: frc))
	}
	
	func testChangesOnInsertedFirstSection() throws {
		let section1 = "1"
		let section2 = "2"
		let e1s2 = Entity(context: context, title: "2-1", section: section2)
		context.processPendingChanges()
		
		let output = Ref([
			Section(name: "2", contents: [e1s2.objectID]),
		])
		let monitor = aggregatorMonitor(for: .init(), output: output)
		
		let frc = createFRC()
		try monitor.startMonitor(controller: frc, context: context)
		
		_ = Entity(context: context, title: "1-1", section: section1)
		_ = Entity(context: context, title: "1-2", section: section1)
		_ = Entity(context: context, title: "1-3", section: section1)
		context.processPendingChanges()
		
		XCTAssertEqual(output.value, sections(from: frc))
	}
	
	func testMoveToNewSection() throws {
		let section1 = "1"
		let section2 = "2"
		let e1s2 = Entity(context: context, title: "2-1", section: section2)
		context.processPendingChanges()
		
		let output = Ref([
			Section(name: "2", contents: [e1s2.objectID]),
		])
		let monitor = aggregatorMonitor(for: .init(), output: output)
//		let monitor = printMonitor
		
		let frc = createFRC()
		try monitor.startMonitor(controller: frc, context: context)
		
		e1s2.title = "1-1"; e1s2.section = section1
		context.processPendingChanges()
		
		XCTAssertEqual(output.value, sections(from: frc))
	}
	
	func testMoveToNewSectionWithModificationsInBoth() throws {
		let section1 = "1"
		let section2 = "2"
		let e1s2 = Entity(context: context, title: "2-1", section: section2)
		context.processPendingChanges()
		
		let output = Ref([
			Section(name: "2", contents: [e1s2.objectID]),
		])
		let monitor = aggregatorMonitor(for: .init(), output: output)
//		let monitor = printMonitor
		
		let frc = createFRC()
		try monitor.startMonitor(controller: frc, context: context)
		
		e1s2.title = "1-1"; e1s2.section = section1
		_ = Entity(context: context, title: "1-2", section: section1)
		_ = Entity(context: context, title: "2-1", section: section2)
		context.processPendingChanges()
		
		XCTAssertEqual(output.value, sections(from: frc))
	}
	
	func testDeleteSectionAndItemsInNextSection() throws {
		let section1 = "1"
		let section2 = "2"
		let e1s1 = Entity(context: context, title: "1-1", section: section1)
		let e1s2 = Entity(context: context, title: "2-1", section: section2)
		let e2s2 = Entity(context: context, title: "2-2", section: section2)
		context.processPendingChanges()
		
		let output = Ref([
			Section(name: section1, contents: [e1s1.objectID]),
			Section(name: section2, contents: [e1s2.objectID, e2s2.objectID]),
		])
		let monitor = aggregatorMonitor(for: .init(), output: output)
		
		let frc = createFRC()
		try monitor.startMonitor(controller: frc, context: context)
		
		context.delete(e1s1)
		context.delete(e1s2)
		context.processPendingChanges()
		
		XCTAssertEqual(output.value, sections(from: frc))
	}
	
	func testInsertInSectionNextToDeletedOne() throws {
		let section1 = "1"
		let section2 = "2"
		let e1s1 = Entity(context: context, title: "1-1", section: section1)
		let e1s2 = Entity(context: context, title: "2-1", section: section2)
		let e2s2 = Entity(context: context, title: "2-2", section: section2)
		context.processPendingChanges()
		
		let output = Ref([
			Section(name: section1, contents: [e1s1.objectID]),
			Section(name: section2, contents: [e1s2.objectID, e2s2.objectID]),
		])
		let monitor = aggregatorMonitor(for: .init(), output: output)
//		let monitor = printMonitor
		
		let frc = createFRC()
		try monitor.startMonitor(controller: frc, context: context)
		
		context.delete(e1s1)
		_ = Entity(context: context, title: "2-3", section: section2)
		context.processPendingChanges()
		
		XCTAssertEqual(output.value, sections(from: frc))
	}
	
	func testTwoConsecutiveSectionInsertsFromMoves() throws {
		let s2e1 = Entity(context: context, title: "2-1", section: "2")
		let s2e2 = Entity(context: context, title: "2-2", section: "2")
		let s4e1 = Entity(context: context, title: "4-1", section: "4")
		let s4e2 = Entity(context: context, title: "4-2", section: "4")
		context.processPendingChanges()
		
		let output = Ref([
			Section(name: "2", contents: [s2e1.objectID, s2e2.objectID]),
			Section(name: "4", contents: [s4e1.objectID, s4e2.objectID]),
		])
		let monitor = aggregatorMonitor(for: .init(), output: output)
//		let monitor = printMonitor
		
		let frc = createFRC()
		try monitor.startMonitor(controller: frc, context: context)
		
		assert(output.value == sections(from: frc))
//		prettyPrintSections("ori: ", output.value)
		
		(s4e1.title, s4e1.section) = ("0-2", "0")
		(s2e2.title, s2e2.section) = ("1-2", "1")
		context.processPendingChanges()
		
//		prettyPrintSections("ref: ", sections(from: frc))
//		prettyPrintSections("cmp: ", output.value)
		XCTAssertEqual(output.value, sections(from: frc))
	}
	
	func testFailureFoundFromRandomTest() throws {
		let s1e0 = Entity(context: context, title: "1-0", section: "1")
		let s1e1 = Entity(context: context, title: "1-1", section: "1")
		let s2e0 = Entity(context: context, title: "2-1", section: "2")
		let s2e1 = Entity(context: context, title: "2-2", section: "2")
		let s3e0 = Entity(context: context, title: "3-0", section: "3")
		let s3e1 = Entity(context: context, title: "3-1", section: "3")
		let s4e0 = Entity(context: context, title: "4-0", section: "4")
		context.processPendingChanges()
		
		let output = Ref([
			Section(name: "1", contents: [s1e0.objectID, s1e1.objectID]),
			Section(name: "2", contents: [s2e0.objectID, s2e1.objectID]),
			Section(name: "3", contents: [s3e0.objectID, s3e1.objectID]),
			Section(name: "4", contents: [s4e0.objectID]),
		])
		let monitor = aggregatorMonitor(for: .init(), output: output)
//		let monitor = printMonitor
		
		let frc = createFRC()
		try monitor.startMonitor(controller: frc, context: context)
		
		XCTAssertEqual(output.value, sections(from: frc))
//		prettyPrintSections("ori: ", output.value)
		
		(s3e1.section, s3e1.title) = ("0", "0-1")
		(s3e0.section, s3e0.title) = ("2", "2-0")
		/* Originally in the extracted failure, but useless for our test. */
//		(s2e0.section, s2e0.title) = ("4", "4-0")
//		(s1e0.section, s1e0.title) = ("4", "4-1")
//		(s4e0.section, s4e0.title) = ("0", "0-0")
		context.processPendingChanges()
		
//		prettyPrintSections("ref: ", sections(from: frc))
//		prettyPrintSections("cmp: ", output.value)
		XCTAssertEqual(output.value, sections(from: frc))
	}
	
	func testLotsOfSeededRandomOperationsOnSingleSection() throws {
		var randomGenerator = SeededGenerator(seed: 6333307901044014058)
		
		let output: Ref<[Section]> = Ref([])
		let monitor = aggregatorMonitor(for: .init(), output: output)
//		let monitor = printMonitor
		
		let frc = createFRC()
		try monitor.startMonitor(controller: frc, context: context)
		
		let possibleSections = ["1"]
		let possibleSectionlessTitles1 = (1...9).map(String.init)
		let possibleSectionlessTitles2 = (1...1420).map(String.init)
		
		var allEntities = [Entity]()
		
		/* First let’s insert a bit of data. */
		let insertedEntities1 = try (0..<7).map{ _ in
			try insertUniqueEntity(sections: possibleSections, sectionlessTitles: possibleSectionlessTitles1, using: &randomGenerator)
		}
		allEntities.append(contentsOf: insertedEntities1)
		context.processPendingChanges()
		XCTAssertEqual(output.value, sections(from: frc))
		
		/* Now let’s move some elements around. */
		for _ in 0..<9 {
			let entity = allEntities.randomElement(using: &randomGenerator)!
			(entity.section, entity.title) = try uniqueEntityDescription(sections: possibleSections, sectionlessTitles: possibleSectionlessTitles1, using: &randomGenerator)
		}
		context.processPendingChanges()
		XCTAssertEqual(output.value, sections(from: frc))
		
		/* Let’s insert more data. */
		let insertedEntities2 = try (0..<420).map{ _ in
			try insertUniqueEntity(sections: possibleSections, sectionlessTitles: possibleSectionlessTitles2, using: &randomGenerator)
		}
		allEntities.append(contentsOf: insertedEntities2)
		context.processPendingChanges()
		XCTAssertEqual(output.value, sections(from: frc))
		
		/* Now let’s move some elements around. */
		for _ in 0..<150 {
			let entity = allEntities.randomElement(using: &randomGenerator)!
			(entity.section, entity.title) = try uniqueEntityDescription(sections: possibleSections, sectionlessTitles: possibleSectionlessTitles2, using: &randomGenerator)
		}
		context.processPendingChanges()
		XCTAssertEqual(output.value, sections(from: frc))
	}
	
	func testLotsOfSeededRandomOperations() throws {
		for seed in [6333307901044014058, 9028641369122766215, 12233175915943776524, 6518433589830160860, 14980529582378505534] as [UInt64] {
			print("seed: \(seed)")
			var randomGenerator = SeededGenerator(seed: seed)
			
			let output: Ref<[Section]> = Ref([])
			let monitor = aggregatorMonitor(for: .init(), output: output)
//			let monitor = printMonitor
			defer {monitor.stopMonitor()}
			
			let frc = createFRC()
			try monitor.startMonitor(controller: frc, context: context)
			
			let possibleSections1 = (1...5).map(String.init)
			let possibleSectionlessTitles1 = (1...7).map(String.init)
			let possibleSections2 = (1...7).map(String.init)
			let possibleSectionlessTitles2 = (1...142).map(String.init)
			let possibleSections3 = (5...13).map(String.init)
			let possibleSectionlessTitles3 = (1...51).map(String.init)
			
			var allEntities = [Entity]()
			
			/* First let’s insert a bit of data. */
			print("Step 1: Inserts.")
			let insertedEntities1 = try (0..<7).map{ _ in
				try insertUniqueEntity(sections: possibleSections1, sectionlessTitles: possibleSectionlessTitles1, using: &randomGenerator)
			}
			allEntities.append(contentsOf: insertedEntities1)
			context.processPendingChanges()
			XCTAssertEqual(output.value, sections(from: frc))
			
			/* Now let’s move some elements around. */
			print("Step 2: Moves.")
			for _ in 0..<9 {
				let entity = allEntities.randomElement(using: &randomGenerator)!
				(entity.section, entity.title) = try uniqueEntityDescription(sections: possibleSections1, sectionlessTitles: possibleSectionlessTitles1, using: &randomGenerator)
			}
			context.processPendingChanges()
			XCTAssertEqual(output.value, sections(from: frc))
			
			/* Let’s insert more data. */
			print("Step 3: More inserts.")
			let insertedEntities2 = try (0..<420).map{ _ in
				try insertUniqueEntity(sections: possibleSections2, sectionlessTitles: possibleSectionlessTitles2, using: &randomGenerator)
			}
			allEntities.append(contentsOf: insertedEntities2)
			context.processPendingChanges()
			XCTAssertEqual(output.value, sections(from: frc))
			
			/* Now let’s move some elements around some more. */
			print("Step 4: More moves.")
			for _ in 0..<150 {
				let entity = allEntities.randomElement(using: &randomGenerator)!
				(entity.section, entity.title) = try uniqueEntityDescription(sections: possibleSections2, sectionlessTitles: possibleSectionlessTitles2, using: &randomGenerator)
			}
			context.processPendingChanges()
			XCTAssertEqual(output.value, sections(from: frc))
			
			/* Let’s move, insert and delete elements randomly. */
			print("Step 5: Moves, inserts and deletes at random.")
			for _ in 0..<250 {
				switch UInt8.random(in: 0..<3, using: &randomGenerator) {
					case 0:
						/* Insert element. */
						let entity = try insertUniqueEntity(sections: possibleSections3, sectionlessTitles: possibleSectionlessTitles3, using: &randomGenerator)
						allEntities.append(entity)
						
					case 1:
						/* Delete element. */
						let idx = allEntities.indices.randomElement(using: &randomGenerator)!
						context.delete(allEntities[idx])
						allEntities.remove(at: idx)
						
					case 2:
						/* Move element. */
						let entity = allEntities.randomElement(using: &randomGenerator)!
						(entity.section, entity.title) = try uniqueEntityDescription(sections: possibleSections3, sectionlessTitles: possibleSectionlessTitles3, using: &randomGenerator)
						
					default:
						fatalError()
				}
			}
			context.processPendingChanges()
			XCTAssertEqual(output.value, sections(from: frc))
			
			/* A bit dirty, but it’ll do. */
			tearDown(); try setUpWithError()
		}
	}
	
	func uniqueEntityDescription<T : RandomNumberGenerator>(sections: [String], sectionlessTitles: [String], using generator: inout T) throws -> (section: String, title: String) {
//		print("searching")
		while true {
			let section = sections.randomElement(using: &generator)!
			let title = section + "-" + sectionlessTitles.randomElement(using: &generator)!
			if try onlyEntity(withTitle: title) == nil {
//				print("found \(title)")
				return (section, title)
			}
		}
	}
	
	@discardableResult
	func insertUniqueEntity<T : RandomNumberGenerator>(sections: [String], sectionlessTitles: [String], using generator: inout T) throws -> Entity {
		let (section, title) = try uniqueEntityDescription(sections: sections, sectionlessTitles: sectionlessTitles, using: &generator)
		return Entity(context: context, title: title, section: section)
	}
	
	func onlyEntity(withTitle title: String, crashOnMultiple: Bool = true) throws -> Entity? {
		let request = Entity.fetchRequest() as! NSFetchRequest<Entity>
		request.predicate = NSPredicate(format: "%K == %@", #keyPath(Entity.title), title)
		let entities = try context.fetch(request)
		guard entities.count < 2 else {
			if crashOnMultiple {fatalError()}
			return nil
		}
		return entities.first
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
//				print(change)
				switch change {
					case let .section(.insert(dstIdx), name):                                                                                     output.value.insert(Section(name: name), at: dstIdx)
					case let .section(.delete(srcIdx), name): assert(output.value[srcIdx].name == name && output.value[srcIdx].contents.isEmpty); output.value.remove(at: srcIdx)
						
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
	
	private func prettyPrintSections(_ prefix: String = "", _ sections: [Section]) {
		print("\(prefix)[")
		sections.forEach{
			print("  \($0.name): ", terminator: "")
			let titles = $0.contents.map{
				let entity = context.object(with: $0) as! Entity
				return entity.title ?? "<notitle>"
			}.joined(separator: ", ")
			print("[\(titles)]")
		}
		print("]")
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
