import Foundation
import ServiceManagement

/// Wraps the modern launch-at-login API (`SMAppService.mainApp`, macOS 13+). No special
/// entitlement is required to register the main app as a login item, and the toggle is
/// mirrored in System Settings → General → Login Items.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers/unregisters the app to launch at login. Throws if the system rejects it
    /// (e.g. the app isn't in a launchable location).
    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled { try service.register() }
        } else {
            if service.status == .enabled { try service.unregister() }
        }
    }
}
