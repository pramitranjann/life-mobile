import SwiftUI

struct SyncDot: View {
    var connected: Bool = true
    var body: some View {
        Circle().fill(connected ? Theme.green : Theme.label).frame(width: 6, height: 6)
    }
}
