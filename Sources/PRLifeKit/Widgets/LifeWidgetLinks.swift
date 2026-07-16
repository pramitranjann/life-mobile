import Foundation

public enum LifeWidgetKind {
    public static let upcoming = "PRLifeUpcoming"
}

public enum LifeWebRoute: Equatable, Sendable {
    case calendar(eventID: String?)
    case tasks(taskID: String?)
    case capture(entryID: String?)

    public var path: String {
        switch self {
        case .calendar(let eventID):
            return Self.path("/life/month", queryName: "event", value: eventID)
        case .tasks(let taskID):
            return Self.path("/life/tasks", queryName: "task", value: taskID)
        case .capture(let entryID):
            return Self.path("/life/history", queryName: "entry", value: entryID)
        }
    }

    private static func path(_ path: String, queryName: String, value: String?) -> String {
        guard let value, !value.isEmpty else { return path }
        var components = URLComponents()
        components.path = path
        components.queryItems = [URLQueryItem(name: queryName, value: value)]
        return components.string ?? path
    }
}

public enum LifeDeepLink {
    public static func event(id: String) -> URL {
        appURL(host: "event", queryItems: [URLQueryItem(name: "id", value: id)])
    }

    public static func task(id: String) -> URL {
        appURL(host: "task", queryItems: [URLQueryItem(name: "id", value: id)])
    }

    public static func capture(context: CaptureContext = .quick) -> URL {
        appURL(host: "capture", queryItems: [URLQueryItem(name: "context", value: context.rawValue)])
    }

    public static var note: URL { appURL(host: "note") }

    public static var settings: URL { appURL(host: "settings") }

    public static func web(_ route: LifeWebRoute) -> URL {
        appURL(host: "web", queryItems: [URLQueryItem(name: "path", value: route.path)])
    }

    private static func appURL(host: String, queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents()
        components.scheme = "prlife"
        components.host = host
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url!
    }
}

#if canImport(WidgetKit)
import WidgetKit

public enum LifeWidgetTimelineReloader {
    public static func reloadUpcoming() {
        WidgetCenter.shared.reloadTimelines(ofKind: LifeWidgetKind.upcoming)
    }
}
#endif
