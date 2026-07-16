import SwiftUI

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
        HStack(spacing: 4) {
            ForEach(MobileCaptureMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Label(mode.label, systemImage: mode.systemImage)
                        .font(Theme.mono(10, .medium))
                        .foregroundStyle(selection == mode ? Theme.bg : Theme.label)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                        .background(selection == mode ? Theme.accent : Color.clear)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.mutedBG)
        .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))
        .animation(.easeOut(duration: 0.16), value: selection)
    }
}
