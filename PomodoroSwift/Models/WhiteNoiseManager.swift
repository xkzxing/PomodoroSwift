//
//  WhiteNoiseManager.swift
//  PomodoroSwift
//
//  Generates white, pink, brown, rain, and campfire noise using AVAudioEngine.
//

import AVFoundation
import Combine

enum NoiseType: String, CaseIterable {
    case white = "white"
    case pink = "pink"
    case brown = "brown"
    case rain = "rain"
    case campfire = "campfire"
    
    var displayName: String {
        switch self {
        case .white: return "White Noise"
        case .pink: return "Pink Noise"
        case .brown: return "Brown Noise"
        case .rain: return "Cozy Rain 🌧️"
        case .campfire: return "Campfire 🔥"
        }
    }
}

// MARK: - Generation State
class AudioState {
    var noiseType: NoiseType = .white
    
    // Pink noise filter state
    var pinkRows: [Float] = Array(repeating: 0.0, count: 16)
    var pinkRunningSum: Float = 0.0
    var pinkIndex: Int = 0
    
    // Brown noise filter state
    var brownLastOutput: Float = 0.0
    var brownLastInput: Float = 0.0
    var brownDCBlock: Float = 0.0
    
    // Rain state (Multi-Layer)
    var rainRumbleLP: Float = 0.0
    var rainHissLP: Float = 0.0
    var rainHissHP: Float = 0.0 // State for High-Pass filter
    var rainDropletFilter: Float = 0.0
    var rainDropletFast: Float = 0.0
    var rainDropletSlow: Float = 0.0
    var rainAirLP: Float = 0.0
    var rainLFOPhase: Float = 0.0
    
    // Campfire state
    var fireRumble: Float = 0.0
    var fireCrackleLP: Float = 0.0
    var fireAirLP: Float = 0.0
    var fireDrift: Float = 0.0
    var resLo1: Float = 0.0, resLo2: Float = 0.0
    var resMid1: Float = 0.0, resMid2: Float = 0.0
    var resHi1: Float = 0.0, resHi2: Float = 0.0
    var resRandLo: Float = 0.0
    var resRandMid: Float = 0.0
    var resRandHi: Float = 0.1
    var freqRandLo: Float = 1.0
    var freqRandMid: Float = 1.0
    var freqRandHi: Float = 1.0
    
    var fireLFOPhase: Float = 0.0
    var fireIntensity: Float = 1.0
    var snapEnvelope: Float = 0.0
    
    var burstCountdown: Float = 0.0
    var burstRemaining: Int = 0
    
    // Campfire parameters
    var cfRumbleMix: Float = 0.4
    var cfTextureMix: Float = 0.3
    var cfWoodyDensity: Float = 0.3
    var cfWoodyLevel: Float = 0.5
    var cfSnapDensity: Float = 0.3
    var cfSnapLevel: Float = 0.35
    var cfRumbleSmooth: Float = 0.95
    var cfTextureSmooth: Float = 0.6
    var cfFreqLo: Float = 300.0
    var cfFreqMid: Float = 900.0
    var cfFreqHi: Float = 2500.0
    var cfResonance: Float = 0.5
    var cfBurstProb: Float = 0.12
}

// MARK: - WhiteNoiseManager

class WhiteNoiseManager: ObservableObject {
    @Published var isPlaying = false
    
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var activeLoopBuffer: AVAudioPCMBuffer?
    private var activeBufferSignature: String?
    
    // Background generation control
    private let bufferQueue = DispatchQueue(label: "noise.buffer.generator", qos: .userInitiated)
    private let generationLock = NSLock()
    private var generationID: Int = 0
    
    // Settings
    private var currentNoiseType: NoiseType = .white
    private var currentVolume: Float = 0.3
    private var currentSampleRate: Double = 48000.0
    private var channelCount: AVAudioChannelCount = 1
    private let loopDuration: Double = 24.0
    
    // Campfire Params
    private var cfParams: (rumble: Float, texture: Float, woodyDensity: Float, woodyLevel: Float, snapDensity: Float, snapLevel: Float, rumbleSmooth: Float, textureSmooth: Float, freqLo: Float, freqMid: Float, freqHi: Float, resonance: Float, burstProb: Float) = (0.4, 0.3, 0.3, 0.5, 0.3, 0.35, 0.95, 0.6, 300.0, 900.0, 2500.0, 0.5, 0.12)
    
    func play() {
        guard !isPlaying else { return }
        
        setupEngineIfNeeded()
        
        do {
            if audioEngine?.isRunning != true {
                try audioEngine?.start()
            }
            isPlaying = true
            if let activeLoopBuffer, activeBufferSignature == currentBufferSignature() {
                try scheduleBufferForPlayback(activeLoopBuffer)
            } else {
                requestBufferRegeneration()
            }
        } catch {
            print("WhiteNoiseManager: Failed to start audio engine: \(error)")
            teardownEngine()
            isPlaying = false
        }
    }
    
    func stop() {
        guard isPlaying || audioEngine != nil else { return }
        invalidatePendingGeneration()
        isPlaying = false
        playerNode?.stop()
        playerNode?.reset()
        teardownEngine()
    }
    
    func setVolume(_ newVolume: Double) {
        currentVolume = Float(newVolume)
        if isPlaying {
            playerNode?.volume = currentVolume
        }
    }
    
    func setCampfireParams(rumble: Double, texture: Double, woodyDensity: Double, woodyLevel: Double, snapDensity: Double, snapLevel: Double, rumbleSmooth: Double, textureSmooth: Double, freqLo: Double, freqMid: Double, freqHi: Double, resonance: Double, burstProb: Double) {
        cfParams = (
            Float(rumble), Float(texture), Float(woodyDensity), Float(woodyLevel),
            Float(snapDensity), Float(snapLevel), Float(rumbleSmooth), Float(textureSmooth),
            Float(freqLo), Float(freqMid), Float(freqHi), Float(resonance), Float(burstProb)
        )
        refreshPlaybackIfNeeded()
    }
    
    func setNoiseType(_ type: NoiseType) {
        currentNoiseType = type
        refreshPlaybackIfNeeded()
    }
    
    // MARK: - Engine Setup
    
    private func setupEngineIfNeeded() {
        if audioEngine != nil {
            return
        }
        
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let mainMixer = engine.mainMixerNode
        let outputFormat = mainMixer.outputFormat(forBus: 0)
        currentSampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 48_000.0
        channelCount = max(1, outputFormat.channelCount)

        let format = AVAudioFormat(standardFormatWithSampleRate: currentSampleRate, channels: channelCount)!
        engine.attach(playerNode)
        engine.connect(playerNode, to: mainMixer, format: format)
        engine.prepare()
        
        self.audioEngine = engine
        self.playerNode = playerNode
    }
    
    private func teardownEngine() {
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
    }
    
    private func refreshPlaybackIfNeeded() {
        guard isPlaying else { return }
        requestBufferRegeneration()
    }
    
    private func scheduleBufferForPlayback(_ buffer: AVAudioPCMBuffer) throws {
        guard let playerNode else {
            throw NSError(domain: "WhiteNoiseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Player node not ready"])
        }
        playerNode.stop()
        playerNode.reset()
        playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        if audioEngine?.isRunning != true {
            try audioEngine?.start()
        }
        playerNode.volume = currentVolume
        playerNode.play()
    }
    
    private func requestBufferRegeneration() {
        guard audioEngine != nil, playerNode != nil else { return }
        
        let generation = nextGenerationID()
        let sampleRate = currentSampleRate
        let channelCount = self.channelCount
        let noiseType = currentNoiseType
        let params = cfParams
        let targetSignature = buildBufferSignature(
            noiseType: noiseType,
            sampleRate: sampleRate,
            channelCount: channelCount,
            params: params
        )
        
        bufferQueue.async { [weak self] in
            guard let self else { return }
            guard self.isGenerationCurrent(generation) else { return }
            
            guard let buffer = self.generateLoopBuffer(
                duration: self.loopDuration,
                sampleRate: sampleRate,
                channelCount: channelCount,
                noiseType: noiseType,
                params: params
            ) else { return }
            
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.isGenerationCurrent(generation), self.isPlaying else { return }
                
                self.activeLoopBuffer = buffer
                self.activeBufferSignature = targetSignature
                
                do {
                    try self.scheduleBufferForPlayback(buffer)
                } catch {
                    print("WhiteNoiseManager: Failed to swap loop buffer: \(error)")
                    self.stop()
                }
            }
        }
    }
    
    private func generateLoopBuffer(
        duration: Double,
        sampleRate: Double,
        channelCount: AVAudioChannelCount,
        noiseType: NoiseType,
        params: (rumble: Float, texture: Float, woodyDensity: Float, woodyLevel: Float, snapDensity: Float, snapLevel: Float, rumbleSmooth: Float, textureSmooth: Float, freqLo: Float, freqMid: Float, freqHi: Float, resonance: Float, burstProb: Float)
    ) -> AVAudioPCMBuffer? {
        guard duration > 0 else { return nil }
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard frameCount > 0 else { return nil }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData else {
            return nil
        }
        
        buffer.frameLength = frameCount
        var channelStates: [AudioState] = (0..<Int(channelCount)).map { _ in
            makeAudioState(noiseType: noiseType, params: params)
        }
        let sampleRate = Float(sampleRate)
        
        for frame in 0..<Int(frameCount) {
            for channel in 0..<Int(channelCount) {
                let sample = WhiteNoiseManager.generateSample(state: channelStates[channel], sampleRate: sampleRate)
                channelData[channel][frame] = sample
            }
        }
        
        return buffer
    }
    
    // MARK: - Helpers
    
    private func makeAudioState(
        noiseType: NoiseType,
        params: (rumble: Float, texture: Float, woodyDensity: Float, woodyLevel: Float, snapDensity: Float, snapLevel: Float, rumbleSmooth: Float, textureSmooth: Float, freqLo: Float, freqMid: Float, freqHi: Float, resonance: Float, burstProb: Float)
    ) -> AudioState {
        let state = AudioState()
        state.noiseType = noiseType
        applyParams(to: state, params: params)
        return state
    }
    
    private func applyParams(
        to state: AudioState,
        params: (rumble: Float, texture: Float, woodyDensity: Float, woodyLevel: Float, snapDensity: Float, snapLevel: Float, rumbleSmooth: Float, textureSmooth: Float, freqLo: Float, freqMid: Float, freqHi: Float, resonance: Float, burstProb: Float)
    ) {
        state.cfRumbleMix = params.rumble
        state.cfTextureMix = params.texture
        state.cfWoodyDensity = params.woodyDensity
        state.cfWoodyLevel = params.woodyLevel
        state.cfSnapDensity = params.snapDensity
        state.cfSnapLevel = params.snapLevel
        state.cfRumbleSmooth = params.rumbleSmooth
        state.cfTextureSmooth = params.textureSmooth
        state.cfFreqLo = params.freqLo
        state.cfFreqMid = params.freqMid
        state.cfFreqHi = params.freqHi
        state.cfResonance = params.resonance
        state.cfBurstProb = params.burstProb
    }
    
    private func currentBufferSignature() -> String {
        buildBufferSignature(
            noiseType: currentNoiseType,
            sampleRate: currentSampleRate,
            channelCount: channelCount,
            params: cfParams
        )
    }
    
    private func buildBufferSignature(
        noiseType: NoiseType,
        sampleRate: Double,
        channelCount: AVAudioChannelCount,
        params: (rumble: Float, texture: Float, woodyDensity: Float, woodyLevel: Float, snapDensity: Float, snapLevel: Float, rumbleSmooth: Float, textureSmooth: Float, freqLo: Float, freqMid: Float, freqHi: Float, resonance: Float, burstProb: Float)
    ) -> String {
        [
            noiseType.rawValue,
            String(format: "%.4f", sampleRate),
            String(channelCount),
            String(format: "%.4f", params.rumble),
            String(format: "%.4f", params.texture),
            String(format: "%.4f", params.woodyDensity),
            String(format: "%.4f", params.woodyLevel),
            String(format: "%.4f", params.snapDensity),
            String(format: "%.4f", params.snapLevel),
            String(format: "%.4f", params.rumbleSmooth),
            String(format: "%.4f", params.textureSmooth),
            String(format: "%.4f", params.freqLo),
            String(format: "%.4f", params.freqMid),
            String(format: "%.4f", params.freqHi),
            String(format: "%.4f", params.resonance),
            String(format: "%.4f", params.burstProb)
        ].joined(separator: "|")
    }
    
    private func nextGenerationID() -> Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        generationID += 1
        return generationID
    }
    
    private func invalidatePendingGeneration() {
        generationLock.lock()
        generationID += 1
        generationLock.unlock()
    }
    
    private func isGenerationCurrent(_ id: Int) -> Bool {
        generationLock.lock()
        defer { generationLock.unlock() }
        return generationID == id
    }
    
    // MARK: - Noise Algorithms
    
    static private func generateSample(state: AudioState, sampleRate: Float) -> Float {
        switch state.noiseType {
        case .white:
            return softLimit(generateWhiteRaw() * 0.34)
        case .pink:
            return softLimit(generatePinkRaw(state: state) * 0.50)
        case .brown:
            return softLimit(generateBrownRaw(state: state) * 0.58)
        case .rain:
            return generateRainNoise(state: state, sampleRate: sampleRate)
        case .campfire:
            return generateCampfireNoise(state: state, sampleRate: sampleRate)
        }
    }
    
    static private func softLimit(_ value: Float) -> Float {
        let scaled = value * 0.9
        return scaled / (1.0 + abs(scaled))
    }
    
    static private func generateWhiteRaw() -> Float {
        return Float.random(in: -1.0...1.0)
    }
    
    static private func generatePinkRaw(state: AudioState) -> Float {
        let white = generateWhiteRaw()
        state.pinkIndex = (state.pinkIndex + 1) % (state.pinkRows.count)
        
        var k = state.pinkIndex
        var numZeros = 0
        if k > 0 {
            while k & 1 == 0 {
                numZeros += 1
                k >>= 1
            }
        }
        
        if numZeros < state.pinkRows.count {
            state.pinkRunningSum -= state.pinkRows[numZeros]
            let newRandom = Float.random(in: -1.0...1.0)
            state.pinkRunningSum += newRandom
            state.pinkRows[numZeros] = newRandom
        }
        
        return (state.pinkRunningSum + white) / Float(state.pinkRows.count + 1)
    }
    
    static private func generateBrownRaw(state: AudioState) -> Float {
        let white = generateWhiteRaw()
        state.brownLastOutput = (state.brownLastOutput + (0.018 * white)) / 1.018
        let dcBlocked = state.brownLastOutput - state.brownLastInput + 0.995 * state.brownDCBlock
        state.brownLastInput = state.brownLastOutput
        state.brownDCBlock = dcBlocked
        return dcBlocked * 2.1
    }
    
    static private func generateRainNoise(state: AudioState, sampleRate: Float) -> Float {
        let pink = generatePinkRaw(state: state)
        let rumbleCoeff: Float = 0.02
        state.rainRumbleLP = state.rainRumbleLP + rumbleCoeff * (pink - state.rainRumbleLP)
        
        let white = generateWhiteRaw()
        let hissLPCoeff: Float = 0.18
        let hissHPCoeff: Float = 0.025
        
        state.rainHissLP = state.rainHissLP + hissLPCoeff * (white - state.rainHissLP)
        let bandPassedHiss = state.rainHissLP - state.rainHissHP
        state.rainHissHP = state.rainHissHP + hissHPCoeff * (bandPassedHiss - state.rainHissHP)
        
        if Float.random(in: 0.0...1.0) < 0.00055 {
            state.rainDropletFast += Float.random(in: 0.12...0.50)
        }
        if Float.random(in: 0.0...1.0) < 0.00012 {
            state.rainDropletSlow += Float.random(in: 0.08...0.35)
        }
        if Float.random(in: 0.0...1.0) < 0.00018 {
            state.rainDropletFilter = Float.random(in: 0.20...0.45)
        }
        
        state.rainDropletFast *= 0.84
        state.rainDropletSlow *= 0.975
        state.rainDropletFilter *= 0.92
        
        let fastDrop = state.rainDropletFast * generateWhiteRaw() * 0.90
        let slowDropSource = generateWhiteRaw() * 0.35 + state.rainRumbleLP * 0.65
        let slowDrop = state.rainDropletSlow * slowDropSource
        let midDrop = state.rainDropletFilter * generateWhiteRaw() * 0.55
        
        state.rainAirLP = state.rainAirLP + 0.004 * (generateWhiteRaw() - state.rainAirLP)
        state.rainLFOPhase += 0.07 * 2.0 * .pi / sampleRate
        if state.rainLFOPhase > 2.0 * .pi { state.rainLFOPhase -= 2.0 * .pi }
        let gust = 0.86 + 0.12 * sin(state.rainLFOPhase) + 0.04 * state.rainAirLP
        
        let output =
            (state.rainRumbleLP * 0.42) +
            (bandPassedHiss * 0.38) +
            (fastDrop * 0.18) +
            (slowDrop * 0.16) +
            (midDrop * 0.14)
        
        return softLimit(output * gust * 1.35)
    }
    
    static private func generateCampfireNoise(state: AudioState, sampleRate: Float) -> Float {
        state.fireLFOPhase += 0.17 * 2.0 * .pi / sampleRate
        if state.fireLFOPhase > 2.0 * .pi { state.fireLFOPhase -= 2.0 * .pi }
        state.fireDrift = state.fireDrift * 0.9996 + Float.random(in: -1.0...1.0) * 0.0006
        let drift = max(0.82, min(1.22, 1.0 + state.fireDrift))
        state.fireIntensity = (1.0 + 0.14 * sin(state.fireLFOPhase)) * drift
        
        let w1 = generateWhiteRaw()
        let rumbleCoeff = 0.955 + state.cfRumbleSmooth * 0.043
        state.fireRumble = state.fireRumble * rumbleCoeff + w1 * (1.0 - rumbleCoeff)
        let rumble = state.fireRumble * 2.8 * state.fireIntensity
        
        let noise = generateWhiteRaw()
        let squared = noise * abs(noise)
        let texCoeff = 0.55 + state.cfTextureSmooth * 0.42
        state.fireCrackleLP = state.fireCrackleLP * texCoeff + squared * (1.0 - texCoeff)
        let texture = state.fireCrackleLP * (0.75 + 0.25 * state.fireIntensity)
        
        state.fireAirLP = state.fireAirLP + 0.03 * (noise - state.fireAirLP)
        let emberAir = (noise - state.fireAirLP) * max(0, state.fireIntensity - 0.82) * 0.55
        let sizzleRaw = (noise - state.fireCrackleLP) * 0.45
        let sizzle = sizzleRaw * max(0, state.fireIntensity - 0.78)
        
        var impulse: Float = 0.0
        let woodyRate = state.cfWoodyDensity * 13.0
        var triggered = false
        
        if state.burstRemaining > 0 {
            state.burstCountdown -= 1.0
            if state.burstCountdown <= 0 {
                impulse = Float.random(in: 0.2...0.7) * (Bool.random() ? 1.0 : -1.0)
                state.burstRemaining -= 1
                state.burstCountdown = Float.random(in: 600...2000)
                triggered = true
            }
        } else {
            let dustProb = woodyRate / sampleRate
            if Float.random(in: 0.0...1.0) < dustProb {
                impulse = Float.random(in: 0.3...0.9) * (Bool.random() ? 1.0 : -1.0)
                triggered = true
                if Float.random(in: 0.0...1.0) < state.cfBurstProb {
                    state.burstRemaining = Int.random(in: 2...3)
                    state.burstCountdown = Float.random(in: 500...1500)
                }
            }
        }
        
        if triggered {
            let rBase = 0.80 + state.cfResonance * 0.19
            state.resRandLo = max(0.8, min(0.99, rBase + Float.random(in: -0.03...0.03)))
            state.resRandMid = max(0.8, min(0.99, rBase + Float.random(in: -0.05...0.05)))
            state.resRandHi = max(0.8, min(0.99, rBase + Float.random(in: -0.02...0.02)))
            
            state.freqRandLo = Float.random(in: 0.85...1.15)
            state.freqRandMid = Float.random(in: 0.85...1.15)
            state.freqRandHi = Float.random(in: 0.85...1.15)
        }
        
        let effRLo = state.resRandLo == 0 ? (0.80 + state.cfResonance * 0.19) : state.resRandLo
        let effRMid = state.resRandMid == 0 ? (0.80 + state.cfResonance * 0.19) : state.resRandMid
        let effRHi = state.resRandHi == 0 ? (0.80 + state.cfResonance * 0.19) : state.resRandHi
        
        let loFreq = state.cfFreqLo * state.freqRandLo
        let loOut = impulse * 0.35 + 2.0 * effRLo * cos(2.0 * .pi * loFreq / sampleRate) * state.resLo1 - effRLo * effRLo * state.resLo2
        state.resLo2 = state.resLo1
        state.resLo1 = loOut
        
        let midFreq = state.cfFreqMid * state.freqRandMid
        let midOut = impulse * 0.45 + 2.0 * effRMid * cos(2.0 * .pi * midFreq / sampleRate) * state.resMid1 - effRMid * effRMid * state.resMid2
        state.resMid2 = state.resMid1
        state.resMid1 = midOut
        
        let hiFreq = state.cfFreqHi * state.freqRandHi
        let hiOut = impulse * 0.25 + 2.0 * effRHi * cos(2.0 * .pi * hiFreq / sampleRate) * state.resHi1 - effRHi * effRHi * state.resHi2
        state.resHi2 = state.resHi1
        state.resHi1 = hiOut
        
        let woodyPop = loOut * 0.35 + midOut * 0.4 + hiOut * 0.25
        let mixed =
            rumble * state.cfRumbleMix +
            texture * state.cfTextureMix +
            sizzle * (state.cfTextureMix * 0.35) +
            emberAir * 0.22 +
            woodyPop * state.cfWoodyLevel +
            state.sharpSnap(sampleRate: sampleRate) * state.cfSnapLevel
        
        return softLimit(mixed * 1.15)
    }
}

extension AudioState {
    func sharpSnap(sampleRate: Float) -> Float {
        let snapRate = cfSnapDensity * 5.0
        let snapProb = snapRate / sampleRate
        if Float.random(in: 0.0...1.0) < snapProb {
            snapEnvelope = max(snapEnvelope, Float.random(in: 0.35...0.85))
        }
        snapEnvelope *= 0.86
        return snapEnvelope * Float.random(in: -1.0...1.0)
    }
}
