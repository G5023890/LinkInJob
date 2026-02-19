import SwiftUI

struct TimelineView: View {
    let events: [ActivityEvent]
    var compact: Bool = false

    var body: some View {
        LazyVStack(alignment: .leading, spacing: compact ? 6 : 8) {
            ForEach(events) { event in
                HStack(alignment: .top, spacing: compact ? 8 : 10) {
                    Image(systemName: symbol(for: event.type))
                        .foregroundStyle(.secondary)
                        .frame(width: compact ? 12 : 14)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.date, style: .date)
                            .font(compact ? .caption2 : .caption)
                            .foregroundStyle(.secondary)
                        Text(event.text)
                            .font(compact ? .caption : .subheadline)
                            .lineLimit(compact ? 2 : nil)
                    }
                }
                .padding(.vertical, compact ? 1 : 2)
            }
        }
    }

    private func symbol(for type: String) -> String {
        switch type {
        case "applied": return "paperplane"
        case "activity": return "bubble.left.and.bubble.right"
        case "manual": return "slider.horizontal.3"
        default: return "clock"
        }
    }
}
