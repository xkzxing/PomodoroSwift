import Combine
import Foundation
#if canImport(PomodoroCore)
import PomodoroCore
#endif

/// The phone worker only reads the chosen directory; it has no source-file writer.
private actor TaskMirrorFileReader {
    func read(directory: URL) throws -> Data {
        let access = directory.startAccessingSecurityScopedResource()
        defer { if access { directory.stopAccessingSecurityScopedResource() } }
        let file = directory.appendingPathComponent(TaskMirrorSnapshot.fileName)
        try? FileManager.default.startDownloadingUbiquitousItem(at: file)
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: file, options: .withoutChanges, error: &coordinationError) { coordinated in
            result = Result {
                if let size = try coordinated.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size > 16 * 1024 * 1024 { throw TaskMirrorError.invalidSnapshot }
                let data = try Data(contentsOf: coordinated)
                guard data.count <= 16 * 1024 * 1024 else { throw TaskMirrorError.invalidSnapshot }
                return data
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
}

@MainActor
final class MobileTaskMirror: ObservableObject {
    @Published private(set) var snapshot: TaskMirrorSnapshot?
    @Published private(set) var folderName: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastReadAt: Date?
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?
    var isConfigured: Bool { directory != nil }

    private let defaults: UserDefaults
    private let reader = TaskMirrorFileReader()
    private let cacheURL: URL
    private var directory: URL?
    private var expectedPublisherID: UUID?
    private var generation = 0
    private var pendingRefresh = false
    private var selectionID: UUID?
    private var cachedSelectionID: UUID?

    private struct Cache: Codable {
        let selectionID: UUID
        let snapshotData: Data
    }

    init(defaults: UserDefaults = .standard, cacheURL: URL? = nil) {
        self.defaults = defaults
        self.cacheURL = cacheURL ?? URL.applicationSupportDirectory.appendingPathComponent("PomodoroMobile", isDirectory: true)
            .appendingPathComponent("desktop-task-cache.json")
        selectionID = defaults.string(forKey: "taskMirror.readSelectionID").flatMap(UUID.init(uuidString:))
        if let data = try? Data(contentsOf: self.cacheURL), let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            snapshot = try? TaskMirrorSnapshot.decode(cache.snapshotData)
            cachedSelectionID = cache.selectionID
        }
        expectedPublisherID = defaults.string(forKey: "taskMirror.acceptedPublisherID").flatMap(UUID.init(uuidString:))
        if cachedSelectionID == selectionID, snapshot != nil { expectedPublisherID = snapshot?.publisherID }
        if let bookmark = defaults.data(forKey: "taskMirror.readDirectoryBookmark") {
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale)
                guard !stale else { throw CocoaError(.fileReadNoPermission) }
                directory = url; folderName = url.lastPathComponent
            } catch { errorMessage = "同步文件夹授权已失效，请重新选择；上次结果仍保留。" }
        }
    }

    func selectDirectory(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: "taskMirror.readDirectoryBookmark")
            generation += 1
            selectionID = UUID()
            defaults.set(selectionID?.uuidString, forKey: "taskMirror.readSelectionID")
            directory = url; folderName = url.lastPathComponent
            expectedPublisherID = nil
            defaults.removeObject(forKey: "taskMirror.acceptedPublisherID")
            errorMessage = nil; statusMessage = "已选择文件夹，点击“立即读取”更新。"
        } catch { errorMessage = "无法保存目录授权，请重新选择文件夹。" }
    }

    func disconnect() {
        generation += 1
        directory = nil; folderName = nil; pendingRefresh = false
        defaults.removeObject(forKey: "taskMirror.readDirectoryBookmark")
        errorMessage = nil; statusMessage = "已停止读取，保留上次的只读副本。"
    }

    func refresh() {
        guard directory != nil else { return }
        pendingRefresh = true
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            while pendingRefresh, let directory, let selectionID {
                pendingRefresh = false
                let session = generation
                do {
                    let data = try await reader.read(directory: directory)
                    let incoming = try TaskMirrorSnapshot.decode(data)
                    guard session == generation else { continue }
                    let current = cachedSelectionID == selectionID && expectedPublisherID == incoming.publisherID ? snapshot : nil
                    if try incoming.shouldReplace(current, expectedPublisherID: expectedPublisherID) {
                        // Only the phone's private offline cache is written.
                        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        let cache = try JSONEncoder().encode(Cache(selectionID: selectionID, snapshotData: data))
                        try cache.write(to: cacheURL, options: [.atomic, .completeFileProtectionUnlessOpen])
                        snapshot = incoming; cachedSelectionID = selectionID
                    }
                    expectedPublisherID = incoming.publisherID
                    defaults.set(incoming.publisherID.uuidString, forKey: "taskMirror.acceptedPublisherID")
                    lastReadAt = Date(); errorMessage = nil
                    statusMessage = incoming.revision < (snapshot?.revision ?? 0)
                        ? "云盘仍在更新，显示本机较新的副本。" : nil
                } catch {
                    guard session == generation else { continue }
                    statusMessage = nil
                    if let mirrorError = error as? TaskMirrorError { errorMessage = mirrorError.localizedDescription }
                    else if (error as NSError).domain == NSCocoaErrorDomain,
                            [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains((error as NSError).code) {
                        errorMessage = "还没有电脑发布的结果，请先在电脑版选择同一个同步文件夹。"
                    } else {
                        errorMessage = "暂时无法读取同步文件，已保留上次结果。请检查网络和文件夹授权后重试。"
                    }
                }
            }
        }
    }
}
