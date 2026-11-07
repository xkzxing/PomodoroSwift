import Combine
import Foundation

@MainActor
final class MobileStore: ObservableObject {
    @Published private(set) var archive: AppArchive
    @Published var errorMessage: String?

    private let fileURL: URL
    private let notifications = TimerNotifications()
    private let ambientAudio = AmbientAudio()
    private var ticker: AnyCancellable?
    private var notificationTask: Task<Void, Never>?
    private var canSave = true
    private var isAppActive = false

    var settings: FocusSettings { archive.settings }
    var timer: FocusTimer { archive.timer }
    init() {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("PomodoroMobile", isDirectory: true)
        fileURL = directory.appendingPathComponent("workspace.json")
        var loaded = AppArchive()
        var loadMessage: String?
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                loaded = try JSONDecoder().decode(AppArchive.self, from: data)
                if loaded.schemaVersion != 1 {
                    canSave = false
                    loaded = AppArchive()
                    loadMessage = "本机数据来自其他版本。为保护原始数据，已暂停保存，请使用兼容版本打开。"
                }
            }
        } catch {
            // Preserve damaged data before allowing a fresh archive to be written.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let backup = directory.appendingPathComponent("recovery-\(Int(Date().timeIntervalSince1970)).json")
                do {
                    try FileManager.default.copyItem(at: fileURL, to: backup)
                    loadMessage = "本机数据未能读取，已保留恢复副本，当前从空白工作区开始。"
                } catch {
                    canSave = false
                    loadMessage = "本机数据未能读取，且无法创建恢复副本。已暂停保存以保护原始数据。"
                }
            } else {
                canSave = false
                loadMessage = "无法创建本机存储目录：\(error.localizedDescription)"
            }
        }
        archive = loaded
        errorMessage = loadMessage
        if archive.reconcileTimer(at: Date()) { save() }
        ambientAudio.onError = { [weak self] message in self?.errorMessage = message }
        notifications.onAction = { [weak self] action, sessionID in
            self?.complete(action, sessionID: sessionID)
        }
        syncServices()
    }

    func setActive(_ active: Bool) {
        isAppActive = active
        tick()
        save()
        syncServices()
    }

    private func updateTicker() {
        // Audible playback permits background execution; stop it at the deadline.
        // Silent sessions rely on the persisted deadline and system notification.
        let needsTicker = timer.status == .running && (isAppActive || settings.shouldPlayAmbient(timerRunning: true))
        if needsTicker && ticker == nil {
            ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick() }
        } else if !needsTicker {
            ticker?.cancel()
            ticker = nil
        }
    }

    private func tick(at now: Date = Date()) {
        guard timer.status == .running else { return }
        if archive.reconcileTimer(at: now) {
            save()
            syncServices()
        }
    }

    func toggleTimer() {
        let now = Date()
        let wasRunning = timer.status == .running
        tick(at: now)
        if wasRunning {
            if timer.status == .running { archive.timer.pause(at: now) }
        } else if timer.status == .completed {
            archive.timer.prepare(mode: archive.nextMode, settings: settings)
            archive.timer.start(at: now)
        } else {
            archive.timer.start(at: now)
        }
        changed()
    }

    func resetTimer() {
        tick()
        archive.timer.prepare(mode: timer.mode, settings: settings)
        changed()
    }

    func selectMode(_ mode: FocusMode) {
        tick()
        archive.timer.prepare(mode: mode, settings: settings)
        changed()
    }

    func complete(_ action: TimerCompletionAction, sessionID: UUID? = nil) {
        let id = sessionID ?? timer.id
        if archive.handleCompletion(action, sessionID: id, at: Date()) { changed() }
    }

    func stopBreak() {
        tick()
        archive.timer.prepare(mode: .focus, settings: settings)
        changed()
    }

    func updateSettings(_ newValue: FocusSettings) {
        let oldDuration = settings.duration(for: timer.mode)
        archive.settings = newValue
        if timer.status == .ready || (timer.status == .paused && oldDuration != newValue.duration(for: timer.mode)) {
            archive.timer.prepare(mode: timer.mode, settings: newValue)
        }
        changed()
    }

    func enableNotifications() async {
        do {
            let allowed = try await notifications.requestPermission()
            archive.settings.notificationsEnabled = allowed
            if !allowed { errorMessage = "通知尚未开启。可在系统设置的通知页面中允许本应用发送提醒。" }
            changed()
        } catch {
            errorMessage = "无法开启通知：\(error.localizedDescription)"
        }
    }

    private func changed() {
        save()
        syncServices()
    }

    private func save() {
        guard canSave else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(archive).write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            errorMessage = "本次更改未能保存，请检查设备可用空间：\(error.localizedDescription)"
        }
    }

    private func syncServices() {
        let snapshot = archive
        let previous = notificationTask
        notificationTask = Task { [notifications] in
            await previous?.value
            do { try await notifications.update(timer: snapshot.timer, enabled: snapshot.settings.notificationsEnabled) }
            catch { self.errorMessage = "到时提醒未能安排：\(error.localizedDescription)" }
        }
        ambientAudio.update(settings: settings, running: timer.status == .running)
        updateTicker()
    }

}
