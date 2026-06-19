import WidgetKit
import SwiftUI

@main
struct PRLifeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        EmptyWidgetPlaceholder()
    }
}

struct EmptyWidgetPlaceholder: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "placeholder", provider: PlaceholderProvider()) { _ in
            Text("PR Life")
        }
    }
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) { completion(SimpleEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: .now)], policy: .never))
    }
}
struct SimpleEntry: TimelineEntry { let date: Date }
