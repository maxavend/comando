import AppKit
import SwiftUI

struct TimestampSeparator: View {
    let date: Date

    var body: some View {
        Text(date.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }
}
