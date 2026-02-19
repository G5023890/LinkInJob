import Foundation

struct ApplicationItem: Identifiable, Codable {
    let id: UUID
    var dbID: Int?
    var company: String
    var role: String
    var location: String
    var subject: String
    var appliedDate: Date?
    var lastActivityDate: Date?
    var autoStage: Stage
    var manualStage: Stage?
    var sourceFilePath: String
    var jobURL: String?
    var descriptionText: String?
    var originalDescriptionText: String?
    var starred: Bool

    var effectiveStage: Stage {
        manualStage ?? autoStage
    }

    var daysSinceLastActivity: Int {
        let referenceDate = lastActivityDate ?? appliedDate ?? Date()
        let days = Calendar.current.dateComponents([.day], from: referenceDate, to: Date()).day ?? 0
        return max(days, 0)
    }

    var needsFollowUp: Bool {
        effectiveStage == .applied && daysSinceLastActivity >= 5
    }
}
