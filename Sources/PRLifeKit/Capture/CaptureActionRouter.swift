import Foundation

/// Bridges App Intents (which may be declared in the widget target but execute in the
/// app process) to the app's live capture stack. The app sets these closures at launch;
/// intents invoke them. Lives in PRLifeKit so both the app and widget targets compile.
@MainActor
public enum CaptureActionRouter {
    public static var start: ((CaptureContext) async -> Void)?
    public static var stop: (() async -> Void)?
}
