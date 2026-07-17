import SwiftUI
import PRLifeKit

enum MobileCaptureMode: String, CaseIterable, Identifiable {
    case voice
    case note
    case task

    var id: String { rawValue }
    var label: String { rawValue.uppercased() + "_" }

    var systemImage: String {
        switch self {
        case .voice: "waveform"
        case .note: "note.text"
        case .task: "checkmark.square"
        }
    }
}

struct CaptureModePicker: View {
    @Binding var selection: MobileCaptureMode

    var body: some View {
        // Neutral segmented control per the web `.segmented`: active item gets
        // panel-2 + brighter text — accent is reserved for primary actions.
        HStack(spacing: 2) {
            ForEach(MobileCaptureMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Label(mode.label, systemImage: mode.systemImage)
                        .font(Theme.mono(12, .medium))
                        .foregroundStyle(selection == mode ? Theme.text : Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                        .background(selection == mode ? Theme.panel2 : Color.clear)
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.mutedBG)
        .overlay(Rectangle().stroke(Theme.border, lineWidth: 1))
        .animation(.easeOut(duration: 0.16), value: selection)
    }
}
