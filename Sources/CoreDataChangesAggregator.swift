import enum CoreData.NSFetchedResultsChangeType
import Foundation
import os.log



public enum AggregatedCoreDataChange<Element> : CustomStringConvertible {
	
	case sectionInsert(dstIdx: Int, String)
	case sectionDelete(srcIdx: Int, String)
	case rowChange(AggregatedSingleSectionCoreDataChange, sectionIdx: Int, Element)
	
	public var description: String {
		switch self {
			case let .sectionInsert(dstIdx, _): return "section-insert(\(dstIdx))"
			case let .sectionDelete(srcIdx, _): return "section-delete(\(srcIdx))"
			case let .rowChange(change, sectionIdx, _): return "row-\(change)-section(\(sectionIdx))"
		}
	}
	
}


public final class CoreDataChangesAggregator<Element> {
	
	public init() {
	}
	
	public func addSectionChange(_ changeType: NSFetchedResultsChangeType, atSectionIndex sectionIndex: Int, sectionName: String) {
		switch changeType.rawValue {
			case NSFetchedResultsChangeType.insert.rawValue: 
				/* Core Data guarantees the section changes are sent _before_ the row changes (says the doc).
				 * We do not support aggregating multiple “waves” of changes:
				 *  all and only the changes between the `controllerWillChangeContent` and `controllerDidChangeContent` method calls must be sent.
				 * We could easily re-order the currentRowAggregators array when starting receiving new section changes,
				 *  but we’d also have to add the support for multiple waves of changes in CoreDataSingleSectionChangesAggregator.
				 * Currently (and probably forever) we do not need this capability.
				 * If you needed later, there is a simpler solution anyway: create an aggregator per wave and iterate on the changes on each aggregator.
				 * Note: The assert is only for insertion. For deletion, the rows in the sections are reported as deleted first, thus contradicting the doc. */
				assert(currentRowAggregators.allSatisfy(\.isEmpty), "Adding section changes must not be done after row changes have been added. More info in the code.")
				currentSectionChanges.append((SectionChange(cdType: changeType, index: sectionIndex), sectionName))
				
			case NSFetchedResultsChangeType.delete.rawValue:
				/* We observed the rows in the deleted sections are reported deleted before the whole section is reported as deleted.
				 * If we have row changes for the deleted section (we should have all the rows in the section reported deleted), we remove these reports. */
				if sectionIndex < currentRowAggregators.count {
					assert(currentRowAggregators[sectionIndex].hasOnlyDeletions)
					currentRowAggregators[sectionIndex].removeAllChanges()
				} else {
					if #available(iOS 14.0, *) {
						Logger.main.notice("Expected rows to have been reported as deleted before the section was reported deleted, but I do not have a row aggregator for deleted section at index \(sectionIndex) (\(sectionName, privacy: .public)). Was the section emtpy? I might also have misunderstood CoreData; would not be the first time…")
					}
				}
				currentSectionChanges.append((SectionChange(cdType: changeType, index: sectionIndex), sectionName))
				
			case NSFetchedResultsChangeType.update.rawValue, NSFetchedResultsChangeType.move.rawValue:
				/* The update and move change type are invalid for a section change.
				 * We only do an assertion failure and not a fatal error because CoreData is capricious and I don’t trust it (see next case). */
				assertionFailure("Invalid change type \(changeType) for a section change.")
				
			default:
				/* We got an unknown section change type.
				 * We only do an assertion failure and not a fatal error to not crash in prod as an abundance of caution.
				 * For row changes we _can_ get invalid change type (see the addRowChange function). */
				assertionFailure("Unknown Core Data change type \(changeType) (section change).")
		}
	}
	
	public func addRowChange(_ changeType: NSFetchedResultsChangeType, atIndexPath srcIndexPath: IndexPath?, newIndexPath dstIndexPath: IndexPath?, for object: Element) {
		let srcSection = srcIndexPath?.section, dstSection = dstIndexPath?.section
		switch (srcSection, dstSection) {
			case let (section?, nil), let (nil, section?): fallthrough
			case (let section?, .some) where section == dstSection: fallthrough
			case (.some, let section?) where section == srcSection:
				ensureEnoughRowAggregators(for: section)
				currentRowAggregators[section].addChange(changeType, atIndexPath: srcIndexPath, newIndexPath: dstIndexPath, for: object)
				
			case let (section1?, section2?):
				switch changeType.rawValue {
					case NSFetchedResultsChangeType.insert.rawValue:
						ensureEnoughRowAggregators(for: section1)
						currentRowAggregators[section1].addChange(changeType, atIndexPath: nil, newIndexPath: dstIndexPath, for: object)
						
					case NSFetchedResultsChangeType.delete.rawValue, NSFetchedResultsChangeType.update.rawValue:
						ensureEnoughRowAggregators(for: section2)
						currentRowAggregators[section2].addChange(changeType, atIndexPath: srcIndexPath, newIndexPath: nil, for: object)
						
					case NSFetchedResultsChangeType.move.rawValue:
						ensureEnoughRowAggregators(for: max(section1, section2))
						currentRowAggregators[section1].addChange(.insert, atIndexPath: nil, newIndexPath: dstIndexPath, for: object)
						currentRowAggregators[section2].addChange(.delete, atIndexPath: srcIndexPath, newIndexPath: nil, for: object)
						
					default:
						/* This case should absolutely never happen but we never know with Core Data (see addChange function in CoreDataSingleSectionChangesAggregator). */
						assertionFailure("Unknown change type \(changeType) (row change).")
				}
				
			case (nil, nil):
				/* This case should absolutely never happen but we never know with Core Data (see addChange function in CoreDataSingleSectionChangesAggregator). */
				assertionFailure("Invalid change with both source and destination index paths that are nil.")
		}
	}
	
	public var isEmpty: Bool {
		(currentSectionChanges.isEmpty && currentRowAggregators.allSatisfy(\.isEmpty))
	}
	
	public func removeAllChanges() {
		currentSectionChanges.removeAll()
		currentRowAggregators.removeAll()
	}
	
	public func iterateAggregatedChanges(andClearChanges clearChanges: Bool = true, _ handler: (AggregatedCoreDataChange<Element>) -> Void) {
		currentSectionChanges.sort(by: { change1, change2 in
			let (change1, change2) = (change1.0, change2.0)
			if change1.isDelete && change2.isInsert {return true}
			if change1.isInsert && change2.isDelete {return false}
			
			if change1.isInsert {assert(change1.index != change2.index); return (change1.index < change2.index)}
			else                {assert(change1.index != change2.index); return (change1.index > change2.index)}
		})
		for currentSectionChange in currentSectionChanges {
			switch currentSectionChange.0 {
				case let .insert(idx): handler(.sectionInsert(dstIdx: idx, currentSectionChange.1))
				case let .delete(idx): handler(.sectionDelete(srcIdx: idx, currentSectionChange.1))
			}
		}
		for (idx, currentRowAggregator) in currentRowAggregators.enumerated() {
			currentRowAggregator.iterateAggregatedChanges(andClearChanges: clearChanges, { change, element in
				handler(.rowChange(change, sectionIdx: idx, element))
			})
		}
		if clearChanges {
			removeAllChanges()
		}
	}
	
	private enum SectionChange : CustomStringConvertible {
		
		case insert(Int)
		case delete(Int)
		
		init(cdType: NSFetchedResultsChangeType, index: Int) {
			switch cdType {
				case .insert: self = .insert(index)
				case .delete: self = .delete(index)
					
				case .move, .update: fallthrough
				@unknown default:
					/* We never allocated a SectionChange with an invalid type for a section change. */
					fatalError("Unreachable code reached.")
			}
		}
		
		var index: Int {
			switch self {
				case let .insert(idx), let .delete(idx):
					return idx
			}
		}
		
		var isInsert: Bool {
			switch self {
				case .insert: return true
				case .delete: return false
			}
		}
		
		var isDelete: Bool {
			switch self {
				case .insert: return false
				case .delete: return true
			}
		}
		
		var description: String {
			switch self {
				case let .insert(idx): return "CoreDataChangesAggregator.SectionChange.insert(\(idx))"
				case let .delete(idx): return "CoreDataChangesAggregator.SectionChange.delete(\(idx))"
			}
		}
		
	}
	
	private var currentSectionChanges = [(SectionChange, String)]()
	private var currentRowAggregators = [CoreDataSingleSectionChangesAggregator<Element>]()
	
	private func ensureEnoughRowAggregators(for sectionIdx: Int) {
		let toAdd = sectionIdx - currentRowAggregators.count + 1
		guard toAdd > 0 else {return}
		
		currentRowAggregators.append(contentsOf: (0..<toAdd).map{ _ in .init() })
	}
	
}
