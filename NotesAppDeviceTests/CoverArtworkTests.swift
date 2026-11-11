import XCTest
import SwiftUI
@testable import NotesApp

@MainActor final class CoverArtworkTests: XCTestCase {
    func testBundledArtworkCatalogAndNativeCoverRendering() throws {
        XCTAssertEqual(CoverStyle.allCases.count, 57)
        var artworkBytes = Set<Data>()
        for style in CoverStyle.allCases {
            if style.artworkIndex != nil {
                let image = try XCTUnwrap(CoverArtwork.image(for: style), style.title)
                XCTAssertGreaterThan(image.size.width, 140)
                XCTAssertGreaterThan(image.size.height, 150)
                artworkBytes.insert(try XCTUnwrap(image.pngData()))
            } else if style.subject != nil {
                XCTAssertNil(CoverArtwork.image(for: style))
                XCTAssertEqual(style.collection, .subjects)
            } else {
                XCTAssertNil(CoverArtwork.image(for: style))
                XCTAssertEqual(style.rawValue, style.accentColor.rawValue)
            }
        }
        XCTAssertEqual(artworkBytes.count, 40)
        // Record the real SwiftUI card treatment for visual inspection of atlas coordinates.
        let sheet = VStack(spacing: 16) {
            ForEach(0..<5) { row in
                HStack(spacing: 16) {
                    ForEach(0..<8) { column in
                        let style = CoverStyle.allCases[5 + row * 8 + column]
                        NotebookCover(title: "Biology", color: style.accentColor, style: style)
                            .frame(width: 128, height: 156)
                    }
                }
            }
        }.padding(20).background(.white).environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 1
        let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
        attachment.name = "Notebook-Cover-Catalog"; attachment.lifetime = .keepAlways
        add(attachment)

        let folder = Folder(title: "University — Biology and Medical Sciences")
        let longTitle = Notebook(title: "Cell Biology — lecture notes and exam preparation")
        let shortTitle = Notebook(title: "Genetics", coverColor: .rose)
        let library = LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .top), count: 3), spacing: 24) {
            FolderCard(folder: folder)
            NotebookCard(notebook: longTitle)
            NotebookCard(notebook: shortTitle)
        }
        .padding(24).frame(width: 740).background(AppTheme.background).environment(\.colorScheme, .light)
        let libraryRenderer = ImageRenderer(content: library)
        libraryRenderer.scale = 1
        let libraryAttachment = XCTAttachment(image: try XCTUnwrap(libraryRenderer.uiImage))
        libraryAttachment.name = "Library-Folders-And-Wrapped-Titles"; libraryAttachment.lifetime = .keepAlways
        add(libraryAttachment)

        let subjects = CoverStyle.allCases.filter { $0.subject != nil }
        XCTAssertEqual(subjects.count, 12)
        let subjectSheet = VStack(spacing: 24) {
            ForEach(0..<3) { row in
                HStack(alignment: .top, spacing: 24) {
                    ForEach(0..<4) { column in
                        let style = subjects[row * 4 + column]
                        VStack(spacing: 8) {
                            NotebookCover(title: "Class Notes", color: style.accentColor, style: style,
                                          isPDF: style == .chemistryCover, favorite: style == .chemistryCover)
                                .frame(width: 180, height: 220)
                            Text(style.title).font(.caption).foregroundStyle(.primary)
                        }
                    }
                }
            }
        }.padding(24).background(AppTheme.background).environment(\.colorScheme, .light)
        let subjectRenderer = ImageRenderer(content: subjectSheet); subjectRenderer.scale = 2
        let subjectAttachment = XCTAttachment(image: try XCTUnwrap(subjectRenderer.uiImage))
        subjectAttachment.name = "Subject-Notebook-Covers"; subjectAttachment.lifetime = .keepAlways; add(subjectAttachment)
    }
}
