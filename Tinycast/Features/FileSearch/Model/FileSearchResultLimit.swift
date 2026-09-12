import Foundation

enum FileSearchResultLimit: Int, CaseIterable, Identifiable, Codable, Sendable {
    case oneHundred = 100
    case twoHundred = 200
    case fiveHundred = 500
    case oneThousand = 1000
    case twoThousand = 2000

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .oneHundred: return "100 results"
        case .twoHundred: return "200 results (Default)"
        case .fiveHundred: return "500 results"
        case .oneThousand: return "1,000 results"
        case .twoThousand: return "2,000 results"
        }
    }
}
