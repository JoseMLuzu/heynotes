// swift-tools-version: 6.0
import PackageDescription

// Host-side tests exercise the same metadata code without requiring a simulator.
let package = Package(
    name: "NotesAppCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "NotesAppCore", targets: ["NotesAppCore"])],
    targets: [
        .target(name: "NotesAppCore", path: "NotesApp", exclude: ["App", "Core/Theme", "Features/Library/Views", "Features/Notebooks", "Resources", "Features/Editor", "Features/Templates", "Features/Covers", "Features/Workspace", "Features/PDF", "Features/Settings", "Core/Components", "Features/Study/Views"],
                sources: ["Core/Models", "Core/Persistence", "Core/Storage", "Features/Library/ViewModels", "Features/Study/Services", "Features/Study/ViewModels"]),
        .testTarget(name: "NotesAppCoreTests", dependencies: ["NotesAppCore"], path: "NotesAppTests")
    ]
)
