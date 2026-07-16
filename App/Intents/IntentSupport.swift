import Foundation
import PRLifeKit

@MainActor
enum PRLifeIntentSupport {
    enum TaskMatch {
        case found(LifeTask)
        case notFound
        case ambiguous
    }

    static func normalizedProject(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func dueLocalDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func savedMessage(
        kind: String,
        project: String?,
        disposition: CaptureWriteDisposition
    ) -> String {
        let destination = normalizedProject(project).map { " — \($0)" } ?? ""
        switch disposition {
        case .uploaded:
            return "Saved \(kind) to PR Life\(destination)."
        case .queued:
            return "Saved \(kind) for retry in PR Life\(destination)."
        }
    }

    static func nextSummary(api: LifeAPIClient, now: Date = Date()) async throws -> String {
        var events: [LifeEvent] = []
        var tasks: [LifeTask] = []
        var firstError: Error?

        do { events = try await api.fetchEvents(date: nil) } catch { firstError = error }
        do { tasks = try await api.fetchTasks() } catch { firstError = firstError ?? error }

        let nextEvent = LifeDashboard.nextEvents(events, limit: 1, now: now).first
        let topTask = LifeDashboard.topTasks(tasks, limit: 1).first
        if let nextEvent, let topTask {
            let eventTitle = nextEvent.title ?? "Untitled event"
            let time = nextEvent.start?.formatted(date: .omitted, time: .shortened)
            let event = time.map { "Your next event is \(eventTitle) at \($0)" }
                ?? "Your next event is \(eventTitle)"
            return "\(event). Your top task is \(topTask.title)."
        }
        if let nextEvent {
            let title = nextEvent.title ?? "Untitled event"
            if let time = nextEvent.start?.formatted(date: .omitted, time: .shortened) {
                return "Your next event is \(title) at \(time)."
            }
            return "Your next event is \(title)."
        }
        if let topTask { return "Your top task is \(topTask.title)." }
        if let firstError { throw firstError }
        return "There are no upcoming events or active tasks in PR Life."
    }

    static func matchingTask(named name: String, in tasks: [LifeTask]) -> LifeTask? {
        if case .found(let task) = taskMatch(named: name, in: tasks) { return task }
        return nil
    }

    static func taskMatch(named name: String, in tasks: [LifeTask]) -> TaskMatch {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .notFound }
        let exact = tasks.filter {
            $0.title.compare(
                query,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }
        if exact.count == 1 { return .found(exact[0]) }
        if exact.count > 1 { return .ambiguous }
        let matches = tasks.filter {
            $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        if matches.count == 1 { return .found(matches[0]) }
        if matches.count > 1 { return .ambiguous }
        return .notFound
    }
}
