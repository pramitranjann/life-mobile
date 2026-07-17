import SwiftUI
import PRLifeKit

struct SquareToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Rectangle().fill(Theme.panel)
                    .overlay(Rectangle().stroke(isOn ? Theme.accentLine : Theme.border, lineWidth: 1))
                    .frame(width: 44, height: 24)
                Rectangle().fill(isOn ? Theme.accent : Theme.label)
                    .frame(width: 16, height: 16).padding(3)
            }
            .frame(width: 44, height: 44)   // 44pt minimum touch target
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .animation(.easeOut(duration: 0.15), value: isOn)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}
