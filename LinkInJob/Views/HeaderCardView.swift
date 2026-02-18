import SwiftUI

struct HeaderCardView: View {
    let item: ApplicationItem

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.company)
                .font(.title3.bold())
            Text(item.role)
                .font(.headline)
            Text(item.location)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(item.effectiveStage.title)
                .font(.caption)
                .foregroundStyle(item.effectiveStage.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(item.effectiveStage.color.opacity(0.16), in: Capsule())

            HStack(spacing: 16) {
                Label {
                    Text(item.appliedDate.map { dateFormatter.string(from: $0) } ?? "n/a")
                } icon: {
                    Image(systemName: "calendar")
                }

                Label {
                    Text("\(item.daysSinceLastActivity) days")
                } icon: {
                    Image(systemName: "clock")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let manual = item.manualStage, manual != item.autoStage {
                Text("Auto: \(item.autoStage.title) • Manual: \(manual.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
