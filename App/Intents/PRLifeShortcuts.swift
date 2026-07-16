import AppIntents

struct PRLifeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartCaptureIntent(), phrases: [
            "Start \(.applicationName) capture",
            "Record with \(.applicationName)",
            "Capture in \(.applicationName)",
        ],
                    shortTitle: "Start Capture", systemImageName: "mic.fill")
        AppShortcut(intent: StopCaptureIntent(), phrases: [
            "Stop \(.applicationName) capture",
            "Save my \(.applicationName) recording",
        ],
                    shortTitle: "Stop Capture", systemImageName: "stop.fill")
        AppShortcut(intent: AddNoteIntent(), phrases: [
            "Add a note to \(.applicationName)",
            "Make a note in \(.applicationName)",
        ], shortTitle: "Add Note", systemImageName: "note.text.badge.plus")
        AppShortcut(intent: AddTaskIntent(), phrases: [
            "Add a task to \(.applicationName)",
            "Create a task in \(.applicationName)",
        ], shortTitle: "Add Task", systemImageName: "checklist")
        AppShortcut(intent: NextInLifeIntent(), phrases: [
            "What's next in \(.applicationName)",
            "What should I do in \(.applicationName)",
        ], shortTitle: "What's Next", systemImageName: "forward.fill")
        AppShortcut(intent: CompleteTaskIntent(), phrases: [
            "Complete a task in \(.applicationName)",
            "Mark a \(.applicationName) task complete",
        ], shortTitle: "Complete Task", systemImageName: "checkmark.circle.fill")
    }
}
