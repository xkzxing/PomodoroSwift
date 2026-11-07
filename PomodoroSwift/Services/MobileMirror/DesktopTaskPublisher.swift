import AppKit
import Combine
import Foundation

@MainActor
final class DesktopTaskPublisher: ObservableObject {
    static let shared = DesktopTaskPublisher()
    @Published private(set) var folderName: String?
    @Published private(set) var isPublishing = false
    @Published private(set) var lastPublishedAt: Date?
    @Published private(set) var errorMessage: String?
    var isConfigured: Bool { directory != nil }

    private let defaults: UserDefaults
    private let writer = DesktopTaskMirrorWriter()
    private let publisherID: UUID
    private var directory: URL?
    private var subscriptions = Set<AnyCancellable>()
    private var lastContents: DesktopTaskMirrorSource.Contents?
    private var generation = 0
    private var pending = false
    private var forcePending = false
    private var started = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let value = defaults.string(forKey: "taskMirror.publisherID"), let id = UUID(uuidString: value) {
            publisherID = id
        } else {
            publisherID = UUID()
            defaults.set(publisherID.uuidString, forKey: "taskMirror.publisherID")
        }
        lastPublishedAt = defaults.object(forKey: "taskMirror.lastPublishedAt") as? Date
        if let bookmark = defaults.data(forKey: "taskMirror.directoryBookmark") {
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale)
                guard !stale else { throw CocoaError(.fileReadNoPermission) }
                directory = url; folderName = url.lastPathComponent
            } catch { errorMessage = "同步文件夹授权已失效，请重新选择。" }
        }
    }

    func start(settings: Settings) {
        // Persist the identity of the initial default panel before its first export.
        if defaults.data(forKey: "todoPanels") == nil,
           let data = try? JSONEncoder().encode(settings.todoPanels) { defaults.set(data, forKey: "todoPanels") }
        startObserving()
    }

    func startObserving() {
        guard !started else { return }
        started = true
        // Establish a baseline without publishing when the app opens.
        lastContents = try? readContents()
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .merge(with: NotificationCenter.default.publisher(for: .todoItemsDidChange))
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.publish() }.store(in: &subscriptions)
    }

    func selectDirectory(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: "taskMirror.directoryBookmark")
            generation += 1
            directory = url; folderName = url.lastPathComponent
            // Bookmark saves also send defaults notifications. Baseline those so
            // they do not race the one explicit export scheduled below.
            lastContents = try? readContents()
            errorMessage = nil
            // Selecting a new directory is an explicit save; export after one second.
            Task { [weak self] in
                let session = self?.generation
                try? await Task.sleep(for: .seconds(1))
                guard let self, session == self.generation else { return }
                self.publish(force: true)
            }
        } catch { errorMessage = "无法保存文件夹授权，请重新选择：\(error.localizedDescription)" }
    }

    func disconnect() {
        generation += 1
        directory = nil; folderName = nil; lastContents = nil; pending = false; forcePending = false
        defaults.removeObject(forKey: "taskMirror.directoryBookmark")
        errorMessage = nil
    }

    func publish(force: Bool = false) {
        guard directory != nil else { return }
        pending = true
        forcePending = forcePending || force
        guard !isPublishing else { return }
        isPublishing = true
        Task {
            defer { isPublishing = false }
            while pending, let directory {
                pending = false
                let force = forcePending; forcePending = false
                let session = generation
                do {
                    let contents = try readContents()
                    if !force && contents == lastContents { continue }
                    let previous = UInt64(defaults.string(forKey: "taskMirror.revision") ?? "0") ?? 0
                    let snapshot = try await writer.publish(panels: contents.panels, directory: directory,
                        publisherID: publisherID, previousRevision: previous, today: contents.today)
                    guard session == generation else { continue }
                    lastContents = contents; lastPublishedAt = snapshot.publishedAt; errorMessage = nil
                    defaults.set(String(snapshot.revision), forKey: "taskMirror.revision")
                    defaults.set(snapshot.publishedAt, forKey: "taskMirror.lastPublishedAt")
                } catch {
                    guard session == generation else { continue }
                    lastContents = nil
                    errorMessage = "未能更新手机同步文件：\(error.localizedDescription)"
                }
            }
        }
    }

    private func readContents() throws -> DesktopTaskMirrorSource.Contents {
        try DesktopTaskMirrorSource.contents(defaults: defaults, coordinates: TodaySkyLocation.shared.coordinates)
    }
}
