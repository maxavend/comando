import SwiftUI

struct SessionAvatar: View {
    let isRunning: Bool
    var emoji: String?
    var colorIndex: Int = 0
    var size: CGFloat = Metrics.avatarSize
    /// What the session works on (a folder or a kind of project).
    var symbol = "apple.terminal.fill"

    var body: some View {
        ZStack {
            if let emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: size * 0.53))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.47, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .background(SessionColor.fill(at: colorIndex), in: .circle)
        .overlay(alignment: .bottomTrailing) {
            if isRunning {
                Circle()
                    .fill(.green)
                    .frame(width: size * 0.31, height: size * 0.31)
                    .overlay(Circle().stroke(.background, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}
