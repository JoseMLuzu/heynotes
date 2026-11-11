import UIKit

/// Displays tiles from the supplied, unmodified gallery asset. No user file is rewritten.
/// Crops omit the gallery gutters; rounded edges/shadows belong to the native cover view.
@MainActor enum CoverArtwork {
    private static let atlas = UIImage(named: "NotebookCoverAtlas")?.cgImage
    private static let tiles: [UIImage?] = (0..<40).map { index in
        guard let atlas else { return nil }
        let columns: [(CGFloat, CGFloat)] = [(47, 205), (236, 391), (421, 576), (606, 762),
                                             (792, 948), (978, 1130), (1160, 1314), (1345, 1501)]
        let rows: [(CGFloat, CGFloat)] = [(24, 221), (247, 438), (463, 631), (657, 819), (845, 1004)]
        let column = columns[index % 8], row = rows[index / 8]
        let rect = CGRect(x: column.0 * CGFloat(atlas.width) / 1536, y: row.0 * CGFloat(atlas.height) / 1024,
                          width: (column.1 - column.0) * CGFloat(atlas.width) / 1536,
                          height: (row.1 - row.0) * CGFloat(atlas.height) / 1024)
        return atlas.cropping(to: rect.integral).map { UIImage(cgImage: $0) }
    }

    static func image(for style: CoverStyle) -> UIImage? {
        guard let index = style.artworkIndex, tiles.indices.contains(index) else { return nil }
        return tiles[index]
    }
}
