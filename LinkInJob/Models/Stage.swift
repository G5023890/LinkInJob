import SwiftUI

enum Stage: String, CaseIterable, Codable {
    case inbox
    case applied
    case interview
    case offer
    case rejected
    case archive

    var title: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .inbox:
            return .secondary
        case .applied:
            return .blue
        case .interview:
            return .orange
        case .offer:
            return .green
        case .rejected:
            return .red
        case .archive:
            return .gray
        }
    }

    var symbol: String {
        switch self {
        case .inbox:
            return "tray"
        case .applied:
            return "paperplane"
        case .interview:
            return "person.2"
        case .offer:
            return "checkmark.seal"
        case .rejected:
            return "xmark.octagon"
        case .archive:
            return "archivebox"
        }
    }
}
