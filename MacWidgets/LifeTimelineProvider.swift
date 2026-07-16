import WidgetKit
import PRLifeKit

struct LifeWidgetDiagnostics {
    let source: String
    let sharedContainerAvailable: Bool
    let fileExists: Bool
    let errorCode: Int?
}

struct LifeEntry: TimelineEntry {
    let date: Date
    let snapshot: LifeSnapshot?
    let diagnostics: LifeWidgetDiagnostics
}

/// Reads the shared snapshot written by the app. Never hits the network.
struct LifeTimelineProvider: TimelineProvider {
    init() { FontRegistration.registerAll() }

    func placeholder(in context: Context) -> LifeEntry {
        LifeEntry(
            date: Date(),
            snapshot: nil,
            diagnostics: LifeWidgetDiagnostics(
                source: "placeholder",
                sharedContainerAvailable: false,
                fileExists: false,
                errorCode: nil
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LifeEntry) -> Void) {
        completion(loadEntry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LifeEntry>) -> Void) {
        let entry = loadEntry(at: Date())
        let next = Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry(at date: Date) -> LifeEntry {
        let sharedDirectory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.id
        )
        let fileURL = sharedDirectory.map(LifeSnapshotLocation.fileURL(in:))
        let fileExists = fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false

        if let snapshot = UserDefaultsLifeSnapshotStore(suiteName: AppGroup.id).load() {
            return LifeEntry(
                date: date,
                snapshot: snapshot,
                diagnostics: LifeWidgetDiagnostics(
                    source: "defaults",
                    sharedContainerAvailable: sharedDirectory != nil,
                    fileExists: fileExists,
                    errorCode: nil
                )
            )
        }

        let fileResult: (source: String, snapshot: LifeSnapshot?, errorCode: Int?) = {
            guard let fileURL else { return ("none", nil, nil) }
            do {
                let data = try Data(contentsOf: fileURL)
                do {
                    let snapshot = try JSONDecoder().decode(LifeSnapshot.self, from: data)
                    NSLog("[PRLife][widget] snapshot read ok path=%@", fileURL.path)
                    return ("file", snapshot, nil)
                } catch {
                    let nsError = error as NSError
                    NSLog(
                        "[PRLife][widget] snapshot decode failed path=%@ domain=%@ code=%ld",
                        fileURL.path,
                        nsError.domain,
                        nsError.code
                    )
                    return ("jsonerr", nil, nsError.code)
                }
            } catch {
                let nsError = error as NSError
                NSLog(
                    "[PRLife][widget] snapshot read failed path=%@ domain=%@ code=%ld",
                    fileURL.path,
                    nsError.domain,
                    nsError.code
                )
                return ("readerr", nil, nsError.code)
            }
        }()

        let diagnosticSource: String
        if fileResult.source != "none" {
            diagnosticSource = fileResult.source
        } else if fileExists {
            diagnosticSource = "fileonly"
        } else {
            diagnosticSource = "none"
        }

        return LifeEntry(
            date: date,
            snapshot: fileResult.snapshot,
            diagnostics: LifeWidgetDiagnostics(
                source: diagnosticSource,
                sharedContainerAvailable: sharedDirectory != nil,
                fileExists: fileExists,
                errorCode: fileResult.errorCode
            )
        )
    }
}
