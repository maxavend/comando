import SwiftUI

struct SessionAvatar: View {
    let isRunning: Bool
    var emoji: String?
    var colorIndex: Int = 0

    var body: some View {
        ZStack {
            if let emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: 17))
            } else {
                Image(systemName: "apple.terminal.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: Metrics.avatarSize, height: Metrics.avatarSize)
        .background(SessionColor.color(at: colorIndex).gradient, in: .circle)
        .overlay(alignment: .bottomTrailing) {
            if isRunning {
                Circle()
                    .fill(.green)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.background, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}
