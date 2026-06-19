import SwiftUI

struct SectionLabel: View {
    let text: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(text).font(Theme.mono(10)).tracking(2).foregroundStyle(Theme.label)
            Spacer()
            if let trailing { Text(trailing).font(Theme.mono(10)).foregroundStyle(Theme.label.opacity(0.6)) }
        }
    }
}
