import SwiftUI

struct SquareToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Rectangle().fill(Theme.panel)
                    .overlay(Rectangle().stroke(isOn ? Theme.accent.opacity(0.4) : Color(hex: "2E2E2E"), lineWidth: 1))
                    .frame(width: 44, height: 24)
                Rectangle().fill(isOn ? Theme.accent : Color(hex: "3A3A3A"))
                    .frame(width: 16, height: 16).padding(3)
            }
        }.buttonStyle(.plain)
    }
}
