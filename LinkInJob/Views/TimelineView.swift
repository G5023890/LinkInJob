import SwiftUI

struct TimelineView: View {
    let events: [ActivityEvent]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(events) { event in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol(for: event.type))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(event.text)
                            .font(.subheadline)
                    }
                }
                .padding(.vertical, 2)
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
