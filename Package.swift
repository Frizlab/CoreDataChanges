// swift-tools-version:5.5
import PackageDescription


let package = Package(
	name: "CoreDataChanges",
	products: [.library(name: "CoreDataChanges", targets: ["CoreDataChanges"])],
	targets: [
		.target(name: "CoreDataChanges", path: "Sources"),
		.testTarget(name: "CoreDataChangesTests", dependencies: ["CoreDataChanges"], path: "Tests"),
	]
)
