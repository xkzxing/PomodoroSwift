import AVFoundation
import Foundation

@MainActor
final class AmbientAudio {
    var onError: ((String) -> Void)?
    private struct Signature: Equatable {
        let sound: AmbientSound
        let campfire: CampfireParameters?
    }
    private var player: AVAudioPlayer?
    private var requested: Signature?
    private var cached: (Signature, Data)?
    private var generationTask: Task<Void, Never>?
    private var worker: Task<Data, Never>?
    private var interruptionObserver: NSObjectProtocol?
    private var settings = FocusSettings()
    private var running = false
    private var interrupted = false

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.interrupted = true
                    self.player?.pause()
                    self.generationTask?.cancel(); self.worker?.cancel(); self.requested = nil
                } else if type == AVAudioSession.InterruptionType.ended.rawValue {
                    self.interrupted = false
                    if options & AVAudioSession.InterruptionOptions.shouldResume.rawValue != 0 {
                        self.update(settings: self.settings, running: self.running)
                    }
                }
            }
        }
    }

    deinit {
        generationTask?.cancel(); worker?.cancel()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    func update(settings: FocusSettings, running: Bool) {
        self.settings = settings
        self.running = running
        guard settings.shouldPlayAmbient(timerRunning: running) else { stop(); return }
        guard !interrupted else { return }
        player?.volume = min(1, max(0, settings.volume))
        let signature = Signature(sound: settings.sound, campfire: settings.sound == .campfire ? settings.campfire.normalized : nil)
        if signature == requested {
            if let player, !player.isPlaying { activateAndPlay(player) }
            return
        }
        generationTask?.cancel(); worker?.cancel()
        requested = signature
        if let (key, data) = cached, key == signature {
            install(data, signature: signature)
            return
        }
        generationTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            let worker = Task.detached(priority: .userInitiated) {
                let samples = NoiseGenerator.samples(sound: signature.sound, count: 48_000 * 60,
                                                      campfire: signature.campfire ?? CampfireParameters())
                if Task.isCancelled || samples.isEmpty { return Data() }
                return Self.waveData(samples)
            }
            self.worker = worker
            let data = await worker.value
            guard !Task.isCancelled, !data.isEmpty, self.requested == signature else { return }
            self.cached = (signature, data)
            self.install(data, signature: signature)
        }
    }

    private func install(_ data: Data, signature: Signature) {
        guard requested == signature, !interrupted, settings.shouldPlayAmbient(timerRunning: running) else { return }
        do {
            let newPlayer = try AVAudioPlayer(data: data)
            newPlayer.numberOfLoops = -1
            newPlayer.volume = min(1, max(0, settings.volume))
            player?.stop()
            player = newPlayer
            activateAndPlay(newPlayer)
        } catch {
            stop()
            onError?("环境声未能播放：\(error.localizedDescription)")
        }
    }

    private func activateAndPlay(_ player: AVAudioPlayer) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            guard player.play() else { throw CocoaError(.featureUnsupported) }
        } catch {
            stop()
            onError?("环境声未能播放：\(error.localizedDescription)")
        }
    }

    private func stop() {
        generationTask?.cancel(); generationTask = nil
        worker?.cancel(); worker = nil; requested = nil
        if player != nil {
            player?.stop(); player = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    nonisolated private static func waveData(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2 + 44)
        func string(_ value: String) { data.append(contentsOf: value.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        let byteCount = UInt32(samples.count * 2)
        string("RIFF"); integer(byteCount + 36); string("WAVEfmt ")
        integer(UInt32(16)); integer(UInt16(1)); integer(UInt16(1))
        integer(UInt32(48_000)); integer(UInt32(96_000)); integer(UInt16(2)); integer(UInt16(16))
        string("data"); integer(byteCount)
        for sample in samples { integer(Int16(sample * Float(Int16.max))) }
        return data
    }
}
