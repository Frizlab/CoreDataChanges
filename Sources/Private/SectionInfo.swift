import Foundation



internal final class SectionInfo : CustomStringConvertible {
	
	var idx: Int
	let name: String
	
	init(idx: Int, name: String) {
		self.idx = idx
		self.name = name
	}
	
	var description: String {
		return "SectionInfo<\(Unmanaged.passUnretained(self).toOpaque())>.idx(\(idx))"
	}
	
}
