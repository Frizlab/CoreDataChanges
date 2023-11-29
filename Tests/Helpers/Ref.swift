import Foundation



internal final class Ref<T> {
	
	var value: T
	
	init(_ v: T) {
		value = v
	}
	
}
