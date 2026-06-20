import SwiftUI
import WidgetKit

@main
struct LifeWidgetBundle: WidgetBundle {
    var body: some Widget {
        LifeWidget()
    }
}

struct LifeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PRLifeWidget", provider: LifeTimelineProvider()) { entry in
            LifeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("PR Life")
        .description("Today's events and due tasks at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
