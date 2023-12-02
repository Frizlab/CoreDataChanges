import Foundation
import GameKit



/* Adapted from <https://stackoverflow.com/a/54849689>. */
class SeededGenerator : RandomNumberGenerator {
	
	let seed: UInt64
	
	init(seed: UInt64) {
		self.seed = seed
		self.source = GKMersenneTwisterRandomSource(seed: seed)
	}
	
	func next() -> UInt64 {
		/* nextInt returns a value between Int32.min and Int32.max. */
		let v1 = UInt32(bitPattern: Int32(source.nextInt()))
		let v2 = UInt32(bitPattern: Int32(source.nextInt()))
		return UInt64(v1) &+ (UInt64(v2) << 32)
	}
	
	private let source: GKMersenneTwisterRandomSource
	
}
