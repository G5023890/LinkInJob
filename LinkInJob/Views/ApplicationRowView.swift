import SwiftUI

struct ApplicationRowView: View {
    let item: ApplicationItem
    let toggleStar: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggleStar) {
                Image(systemName: item.starred ? "star.fill" : "star")
                    .foregroundStyle(item.starred ? .yellow : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.company)
                    .font(.headline)
                    .fontWeight(.bold)
                Text(item.role)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(item.location)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(item.effectiveStage.title)
                    .font(.caption)
                    .foregroundStyle(item.effectiveStage.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(item.effectiveStage.color.opacity(0.15), in: Capsule())

                Text("\(item.daysSinceLastActivity)d")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
