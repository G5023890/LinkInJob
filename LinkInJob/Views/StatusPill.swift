import SwiftUI

struct StatusPill: View {
    let stage: Stage

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(stage.color)
                .frame(width: 7, height: 7)
            Text(stage.title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(stage.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(stage.color.opacity(0.16), in: Capsule())
    }
}
