import SwiftUI
import PRLifeKit

struct RecordButton: View {
    let isRecording: Bool
    var onPress: () -> Void
    var onRelease: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        // Mirrors the web `.life-mic`: accent outline idle, solid accent while
        // live — solid accent fill is reserved for the recording state.
        HStack {
            Circle()
                .fill(isRecording ? Theme.bg : Theme.accent)
                .frame(width: 9, height: 9)
                .opacity(isRecording && pulsing ? 0.35 : 1)
                .scaleEffect(isRecording && pulsing ? 0.7 : 1)
            Text(isRecording ? "RECORDING_" : "RECORD")
                .font(Theme.mono(13, .medium))
                .tracking(2)
                .foregroundStyle(isRecording ? Theme.bg : Theme.accent)
            Spacer()
            Text(isRecording ? "RELEASE TO STOP" : "HOLD TO CAPTURE")
                .font(Theme.mono(11))
                .foregroundStyle(isRecording ? Theme.bg.opacity(0.75) : Theme.label)
        }
        .padding(.horizontal, 20).frame(height: 46)
        .background(isRecording ? Theme.accent : Color.clear)
        .overlay(Rectangle().stroke(Theme.accent, lineWidth: 1))
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !isRecording { onPress() } }
            .onEnded { _ in onRelease() })
        .onChange(of: isRecording) { _, recording in
            if recording && !reduceMotion {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { pulsing = false }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isRecording ? "Stop recording" : "Record")
        .accessibilityHint(isRecording ? "Double-tap to stop" : "Double-tap to start recording")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            // VoiceOver can't hold-to-record; activate toggles instead.
            isRecording ? onRelease() : onPress()
        }
    }
}
