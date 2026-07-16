import AVFoundation
import Foundation
import PRLifeKit
import UIKit

struct AudioInputDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let portType: String
    let supportsHighQualityBluetoothRecording: Bool
    let isHighQualityBluetoothRecordingEnabled: Bool
}

enum AudioRecordingStopReason: String, Equatable, Sendable {
    case requested
    case routeUnavailable
    case interrupted
    case mediaServicesReset
    case encoderError
    case systemStopped
}

struct RetainedAudioRecording: Equatable, Sendable {
    let fileName: String
    let duration: TimeInterval
    let reason: AudioRecordingStopReason
    let input: AudioInputDescriptor?
}

enum AudioRecorderEvent: Equatable, Sendable {
    case routeChanged(
        reasonRawValue: UInt,
        currentInput: AudioInputDescriptor?,
        availableInputs: [AudioInputDescriptor]
    )
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case enteredBackground
    case enteredForeground
    case mediaServicesReset
    case recordingStopped(RetainedAudioRecording)
}

/// Plain-value lifecycle input that tests can feed directly without manufacturing
/// Notification objects or changing the process-wide AVAudioSession.
enum AudioSessionSystemEvent: Equatable, Sendable {
    case routeChanged(reasonRawValue: UInt)
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case enteredBackground
    case enteredForeground
    case mediaServicesReset
}

enum AudioInputSelectionError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "The selected microphone is no longer available."
    }
}

final class AVAudioRecorderService: NSObject, AudioRecording, AVAudioRecorderDelegate, @unchecked Sendable {
    typealias EventHandler = (AudioRecorderEvent) -> Void

    private let session: AVAudioSession
    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var recorder: AVAudioRecorder?
    private var currentFileName: String?
    private var recordingInput: AudioInputDescriptor?

    private(set) var isRecording = false
    var onEvent: EventHandler?

    init(
        session: AVAudioSession = .sharedInstance(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.session = session
        self.notificationCenter = notificationCenter
        super.init()
        observeAudioLifecycle()
    }

    deinit {
        observers.forEach(notificationCenter.removeObserver)
    }

    static var capturesDir: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("captures", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.none]
        )
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.none],
            ofItemAtPath: dir.path
        )
        return dir
    }

    var currentInput: AudioInputDescriptor? {
        session.currentRoute.inputs.first.map(Self.describe)
            ?? session.preferredInput.map(Self.describe)
    }

    var availableInputs: [AudioInputDescriptor] {
        (session.availableInputs ?? []).map(Self.describe)
    }

    var selectedInputRoute: AudioInputRoute? {
        let input = recordingInput ?? currentInput
        return input.map {
            AudioInputRoute(identifier: $0.id, name: $0.name, portType: $0.portType)
        }
    }

    /// Prepares the recording category so iOS exposes Bluetooth microphones before
    /// capture begins. The returned snapshot is valid for presenting a picker; route
    /// change events provide refreshed snapshots afterward.
    func prepareInputSelection() async throws -> [AudioInputDescriptor] {
        try configureSessionForRecording()
        let shouldDeactivate = !isRecording
        if shouldDeactivate {
            try session.setActive(true)
        }
        let inputs = availableInputs
        if shouldDeactivate {
            deactivateSession()
        }
        return inputs
    }

    /// Selects a concrete input by its stable AVAudioSession UID. Passing nil
    /// restores system route selection.
    func selectInput(id: String?) throws {
        guard let id else {
            try session.setPreferredInput(nil)
            return
        }
        guard let input = session.availableInputs?.first(where: { $0.uid == id }) else {
            throw AudioInputSelectionError.unavailable
        }
        try session.setPreferredInput(input)
    }

    func start() async throws -> String {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard granted else { throw RecordingError.permissionDenied }

        do {
            try configureSessionForRecording()
            try session.setActive(true)
            try? session.setPrefersNoInterruptionsFromSystemAlerts(true)
        } catch {
            throw RecordingError.sessionFailed("\(error)")
        }

        let name = "capture-\(UUID().uuidString).m4a"
        let url = Self.capturesDir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [
                .protectionKey: FileProtectionType.none
            ])
        } else {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.none],
                ofItemAtPath: url.path
            )
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.prepareToRecord()
            guard recorder.record() else {
                deactivateSession()
                throw RecordingError.sessionFailed("Recording could not start.")
            }
            self.recorder = recorder
            currentFileName = name
            recordingInput = currentInput
            isRecording = recorder.isRecording
            return name
        } catch {
            deactivateSession()
            throw RecordingError.sessionFailed("\(error)")
        }
    }

    func stop() async -> TimeInterval {
        stopKeepingPartial(reason: .requested)?.duration ?? 0
    }

    /// Handles normalized lifecycle events. Keeping this separate from Notification
    /// parsing makes route/interruption behavior directly unit-testable.
    func handleSystemEvent(_ event: AudioSessionSystemEvent) {
        switch event {
        case .routeChanged(let reasonRawValue):
            onEvent?(.routeChanged(
                reasonRawValue: reasonRawValue,
                currentInput: currentInput,
                availableInputs: availableInputs
            ))
            if reasonRawValue == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                stopForSystemEvent(reason: .routeUnavailable)
            } else {
                recordingInput = currentInput
            }
        case .interruptionBegan:
            onEvent?(.interruptionBegan)
            stopForSystemEvent(reason: .interrupted)
        case .interruptionEnded(let shouldResume):
            onEvent?(.interruptionEnded(shouldResume: shouldResume))
        case .enteredBackground:
            // Background audio is supported by the app. Observe this transition but
            // do not stop; locking the phone must preserve an active capture.
            onEvent?(.enteredBackground)
        case .enteredForeground:
            onEvent?(.enteredForeground)
        case .mediaServicesReset:
            stopForSystemEvent(reason: .mediaServicesReset)
            onEvent?(.mediaServicesReset)
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        guard recorder === self.recorder else { return }
        stopForSystemEvent(reason: .encoderError)
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard recorder === self.recorder, isRecording else { return }
        stopForSystemEvent(reason: flag ? .systemStopped : .encoderError)
    }

    private func configureSessionForRecording() throws {
        var options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP]
        if #available(iOS 26.0, *) {
            options.insert(.bluetoothHighQualityRecording)
        }
        // Bluetooth high-quality recording is only compatible with `.default`.
        // HFP remains the fallback on unsupported routes and on iOS 17–25.
        try session.setCategory(.playAndRecord, mode: .default, options: options)
    }

    @discardableResult
    private func stopKeepingPartial(reason: AudioRecordingStopReason) -> RetainedAudioRecording? {
        guard let recorder else {
            isRecording = false
            return nil
        }

        let retained = RetainedAudioRecording(
            fileName: currentFileName ?? recorder.url.lastPathComponent,
            duration: recorder.currentTime,
            reason: reason,
            input: recordingInput ?? currentInput
        )

        // Clear our active state before asking AVAudioRecorder to finish, because
        // its delegate can be called synchronously. AVAudioRecorder.stop() finalizes
        // the existing m4a; the file is deliberately never removed here.
        self.recorder = nil
        currentFileName = nil
        recordingInput = nil
        isRecording = false
        recorder.stop()
        deactivateSession()
        onEvent?(.recordingStopped(retained))
        return retained
    }

    private func stopForSystemEvent(reason: AudioRecordingStopReason) {
        guard isRecording else { return }
        _ = stopKeepingPartial(reason: reason)
    }

    private func deactivateSession() {
        try? session.setPrefersNoInterruptionsFromSystemAlerts(false)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observeAudioLifecycle() {
        observe(AVAudioSession.routeChangeNotification) { [weak self] notification in
            let rawValue = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?
                .uintValue ?? AVAudioSession.RouteChangeReason.unknown.rawValue
            self?.handleSystemEvent(.routeChanged(reasonRawValue: rawValue))
        }
        observe(AVAudioSession.interruptionNotification) { [weak self] notification in
            guard let rawType = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?
                .uintValue,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
            switch type {
            case .began:
                self?.handleSystemEvent(.interruptionBegan)
            case .ended:
                let rawOptions = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?
                    .uintValue ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                    .contains(.shouldResume)
                self?.handleSystemEvent(.interruptionEnded(shouldResume: shouldResume))
            @unknown default:
                return
            }
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
            self?.handleSystemEvent(.mediaServicesReset)
        }
        observe(UIApplication.didEnterBackgroundNotification) { [weak self] _ in
            self?.handleSystemEvent(.enteredBackground)
        }
        observe(UIApplication.willEnterForegroundNotification) { [weak self] _ in
            self?.handleSystemEvent(.enteredForeground)
        }
    }

    private func observe(
        _ name: Notification.Name,
        using block: @escaping (Notification) -> Void
    ) {
        observers.append(notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main,
            using: block
        ))
    }

    private static func describe(_ input: AVAudioSessionPortDescription) -> AudioInputDescriptor {
        var supportsHighQuality = false
        var highQualityEnabled = false
        if #available(iOS 26.0, *),
           let capability = input.bluetoothMicrophoneExtension?.highQualityRecording {
            supportsHighQuality = capability.isSupported
            highQualityEnabled = capability.isEnabled
        }
        return AudioInputDescriptor(
            id: input.uid,
            name: input.portName,
            portType: input.portType.rawValue,
            supportsHighQualityBluetoothRecording: supportsHighQuality,
            isHighQualityBluetoothRecordingEnabled: highQualityEnabled
        )
    }
}
