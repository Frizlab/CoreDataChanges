import Foundation
import os.log



@available(iOS 14.0, *)
extension Logger {
	
	static let main = {
		return Logger(subsystem: subsystem, category: "Main")
	}()
	
	private static let subsystem = "me.frizlab.core-data-changes"
	
}
