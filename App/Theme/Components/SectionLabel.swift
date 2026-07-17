import SwiftUI
import PRLifeKit

struct SectionLabel: View {
    let text: String
    var trailing: String? = nil
    var body: some View {
        // Web `.eyebrow`: 11px mono, 0.16em tracking, label color.
        HStack {
            Text(text).font(Theme.mono(11)).tracking(1.7).foregroundStyle(Theme.label)
            Spacer()
            if let trailing { Text(trailing).font(Theme.mono(11)).foregroundStyle(Theme.label) }
        }
    }
}
