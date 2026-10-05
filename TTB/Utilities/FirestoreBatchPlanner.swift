import Foundation

enum FirestoreBatchPlanner {
    static func ranges(itemCount: Int, limit: Int) -> [Range<Int>] {
        guard itemCount > 0, limit > 0 else { return [] }

        var ranges: [Range<Int>] = []
        var startIndex = 0

        while startIndex < itemCount {
            let remainingCount = itemCount - startIndex
            let endIndex = remainingCount > limit
                ? startIndex + limit
                : itemCount
            ranges.append(startIndex..<endIndex)
            startIndex = endIndex
        }

        return ranges
    }
}
