import Foundation

extension EditorTool {
    var guidance: String {
        switch self {
        case .lasso: "Draw a loop around handwriting, then move the selection. Touch and hold selected ink for editing actions."
        case .objects: "Select an inserted object, drag it to move, or drag its corner to resize."
        case .laser: "Write or point with Apple Pencil. Each trail stays for 3 seconds after lifting, then fades. It is not saved or exported."
        case .stamp: "Tap the page to place the selected stamp. Use Select Objects to move or resize it."
        case .sticky: "Tap to add a note. Tap its header with a finger to fold it. Use Select Objects to move or edit it."
        case .protractor: "Tap the vertex, then one point on each arm. A fourth tap resets the measurement. Measurements are temporary."
        case .compass: "Drag from the center to set a radius and create a circle. Radius uses logical page points."
        case .capture: "Drag with Apple Pencil to select a region to copy or share as an image."
        case .cardCapture: "Select a question region, then choose an answer region to create a linked study card."
        case .pdfHighlight: "Drag across selectable PDF text. Scanned pages need a text layer; original PDFs stay intact."
        case .writingZoom: "Select a region to write at a larger size while keeping the page overview visible."
        default: "Drag on the page to create study tape. Tap tape with a finger to reveal or cover the answer."
        }
    }
}
