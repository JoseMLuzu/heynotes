import Foundation

enum PDFPageSelectionError: LocalizedError {
    case empty, invalidRange, outsideDocument(Int)
    var errorDescription: String? {
        switch self {
        case .empty: "Select at least one page."
        case .invalidRange: "Use page numbers or ranges, such as 1, 3–5, 8."
        case .outsideDocument(let count): "Enter page numbers between 1 and \(count)."
        }
    }
}

enum PDFPageSelection {
    /// User-facing numbers are one-based; stored PDF references remain zero-based.
    static func parse(_ text: String, pageCount: Int) throws -> [Int] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PDFPageSelectionError.empty }
        let normalized = text.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
        var result = Set<Int>()
        for token in normalized.split(separator: ",", omittingEmptySubsequences: false) {
            let values = token.split(separator: "-", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard (1...2).contains(values.count), let first = Int(values[0]),
                  let last = Int(values.last ?? ""), first <= last else { throw PDFPageSelectionError.invalidRange }
            guard first >= 1, last <= pageCount else { throw PDFPageSelectionError.outsideDocument(pageCount) }
            result.formUnion((first - 1)..<last)
        }
        return try validated(Array(result), pageCount: pageCount)
    }

    static func validated(_ indices: [Int], pageCount: Int) throws -> [Int] {
        guard !indices.isEmpty else { throw PDFPageSelectionError.empty }
        guard pageCount > 0, indices.allSatisfy({ $0 >= 0 && $0 < pageCount }) else {
            throw PDFPageSelectionError.outsideDocument(pageCount)
        }
        return Set(indices).sorted()
    }
}
