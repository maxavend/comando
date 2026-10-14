import SwiftUI

struct SessionAvatar: View {
    let isRunning: Bool

    var body: some View {
        Image(systemName: "apple.terminal.fill")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(
                LinearGradient(colors: [Color(white: 0.62), Color(white: 0.45)], startPoint: .top, endPoint: .bottom),
                in: .circle
            )
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
