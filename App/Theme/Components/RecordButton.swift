import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    var onPress: () -> Void
    var onRelease: () -> Void
    var body: some View {
        HStack {
            Circle().fill(Theme.accent).frame(width: 7, height: 7)
            Text(isRecording ? "RECORDING_" : "RECORD")
                .font(Theme.mono(11, .medium))
                .tracking(2)
                .foregroundStyle(Theme.accent)
            Spacer()
            Text(isRecording ? "RELEASE TO STOP" : "HOLD TO CAPTURE")
                .font(Theme.mono(10))
                .foregroundStyle(isRecording ? Theme.accent.opacity(0.8) : Color(hex: "3A3A3A"))
        }
        .padding(.horizontal, 20).frame(height: 44)
        .background(Theme.accent.opacity(isRecording ? 0.12 : 0.07))
        .overlay(Rectangle().stroke(Theme.accent.opacity(isRecording ? 0.65 : 0.35), lineWidth: 1))
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !isRecording { onPress() } }
            .onEnded { _ in onRelease() })
    }
}
