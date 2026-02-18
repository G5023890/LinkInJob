import Foundation

struct ActivityEvent: Identifiable {
    let id = UUID()
    let date: Date
    let type: String
    let text: String
}
