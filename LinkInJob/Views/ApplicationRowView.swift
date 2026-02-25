import SwiftUI

struct ApplicationRowView: View {
    let item: ApplicationItem
    let isSelected: Bool
    let toggleStar: () -> Void
    @State private var isHovered = false

    private var displayDate: Date? {
        item.lastActivityDate ?? item.appliedDate
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: toggleStar) {
                Image(systemName: item.starred ? "star.fill" : "star")
                    .foregroundStyle(item.starred ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.effectiveStage.color)
                        .frame(width: 8, height: 8)

                    Text(item.company)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Text(item.role)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 4) {
                if let displayDate {
                    Text(displayDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(item.effectiveStage.title)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            rowBackgroundColor,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private var rowBackgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }
        if isHovered {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.08)
        }
        return .clear
    }
}
