//
//  WhiteNoiseManager.swift
//  PomodoroSwift
//
//  Generates white, pink, brown, campfire, or "cozy" rain noise using AVAudioEngine.
//  Startup strategy:
//  1. Generate a 60-second loop buffer once.
//  2. Loop playback with AVAudioPlayerNode.
//  3. Do not rebuild continuously on campfire parameter slider updates.
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
    
    // Rain state (Multi-Layer)
    var rainRumbleLP: Float = 0.0
    var rainHissLP: Float = 0.0
    var rainHissHP: Float = 0.0 // State for High-Pass filter
    var rainDropletFilter: Float = 0.0
    var rainLFOPhase: Float = 0.0
    
    // Campfire state
    var fireRumble: Float = 0.0
    var fireCrackleLP: Float = 0.0
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

    // Generation control
    private let generationLock = NSLock()
    private var generationID: Int = 0
    
    // Buffer cache
    private var cachedBuffer: AVAudioPCMBuffer?
    private var cachedSignature: String?
    
    // Background generation queue
    private let bufferQueue = DispatchQueue(label: "noise.buffer.generator", qos: .userInitiated)
    
    // Settings
    private var currentNoiseType: NoiseType = .white
    private var currentVolume: Float = 0.3
    private var currentSampleRate: Double = 48000.0
    
    // Config
    private let loopDuration: Double = 60.0
    
    // Campfire Params
    private var cfParams: (rumble: Float, texture: Float, woodyDensity: Float, woodyLevel: Float, snapDensity: Float, snapLevel: Float, rumbleSmooth: Float, textureSmooth: Float, freqLo: Float, freqMid: Float, freqHi: Float, resonance: Float, burstProb: Float) = (0.4, 0.3, 0.3, 0.5, 0.3, 0.35, 0.95, 0.6, 300.0, 900.0, 2500.0, 0.5, 0.12)
    
    func play() {
        guard !isPlaying else { return }

        do {
            try setupEngineIfNeeded()
            if audioEngine?.isRunning != true {
                try audioEngine?.start()
            }
            isPlaying = true

            let signature = currentBufferSignature()
            if let cache = cachedBuffer, cachedSignature == signature {
                try scheduleBufferForPlayback(cache)
            } else {
                requestLoopBufferGeneration()
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
        
        let previousSignature = currentBufferSignature()
        // Update local params
        cfParams = (
            Float(rumble), Float(texture), Float(woodyDensity), Float(woodyLevel),
            Float(snapDensity), Float(snapLevel), Float(rumbleSmooth), Float(textureSmooth),
            Float(freqLo), Float(freqMid), Float(freqHi), Float(resonance), Float(burstProb)
        )
        guard currentBufferSignature() != previousSignature else { return }
        invalidateBufferCache()
        if isPlaying && currentNoiseType == .campfire {
            requestLoopBufferGeneration()
        }
    }
    
    func setNoiseType(_ type: NoiseType) {
        guard currentNoiseType != type else { return }
        currentNoiseType = type
        invalidateBufferCache()
        guard isPlaying else { return }
        requestLoopBufferGeneration()
    }
    
    // MARK: - Engine Setup
    
    private func setupEngineIfNeeded() throws {
        if audioEngine != nil {
            return
        }
        
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let mainMixer = engine.mainMixerNode
        let outputFormat = mainMixer.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate
        guard sampleRate.isFinite, sampleRate > 0,
              let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
              ) else {
            throw NSError(
                domain: "WhiteNoiseManager",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "No valid audio output format"]
            )
        }
        currentSampleRate = sampleRate

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
    
    private func scheduleBufferForPlayback(_ buffer: AVAudioPCMBuffer) throws {
        guard let playerNode else {
            throw NSError(
                domain: "WhiteNoiseManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Player node not ready"]
            )
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
    
    // MARK: - Buffer Generation

    private func requestLoopBufferGeneration() {
        guard audioEngine != nil, playerNode != nil else { return }

        let generation = nextGenerationID()
        let sampleRate = currentSampleRate
        let noiseType = currentNoiseType
        let params = cfParams
        let targetSignature = buildBufferSignature(
            noiseType: noiseType,
            sampleRate: sampleRate,
            params: params
        )

        bufferQueue.async { [weak self] in
            guard let self else { return }
            guard self.isGenerationCurrent(generation) else { return }

            let state = self.makeAudioState(noiseType: noiseType, params: params)
            guard let buffer = self.generatePCMBuffer(
                state: state,
                sampleRate: sampleRate,
                duration: self.loopDuration
            ) else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.isGenerationCurrent(generation), self.isPlaying else { return }

                self.cachedBuffer = buffer
                self.cachedSignature = targetSignature

                do {
                    try self.scheduleBufferForPlayback(buffer)
                } catch {
                    print("WhiteNoiseManager: Failed to schedule loop buffer: \(error)")
                    self.stop()
                }
            }
        }
    }

    private func generatePCMBuffer(state: AudioState, sampleRate: Double, duration: Double) -> AVAudioPCMBuffer? {
        guard sampleRate.isFinite, sampleRate > 0, duration.isFinite, duration > 0,
              let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
              ) else { return nil }
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
              ) else { return nil }
        
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        
        for i in 0..<Int(frameCount) {
            channelData[i] = WhiteNoiseManager.generateSample(state: state, sampleRate: Float(sampleRate))
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
            params: cfParams
        )
    }

    private func buildBufferSignature(
        noiseType: NoiseType,
        sampleRate: Double,
        params: (rumble: Float, texture: Float, woodyDensity: Float, woodyLevel: Float, snapDensity: Float, snapLevel: Float, rumbleSmooth: Float, textureSmooth: Float, freqLo: Float, freqMid: Float, freqHi: Float, resonance: Float, burstProb: Float)
    ) -> String {
        [
            noiseType.rawValue,
            String(format: "%.4f", sampleRate),
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

    private func invalidateBufferCache() {
        cachedBuffer = nil
        cachedSignature = nil
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
            return generateWhiteNoise()
        case .pink:
            return generatePinkNoise(state: state)
        case .brown:
            return generateBrownNoise(state: state)
        case .rain:
            return generateRainNoise(state: state, sampleRate: sampleRate)
        case .campfire:
            return generateCampfireNoise(state: state, sampleRate: sampleRate)
        }
    }
    
    static private func generateWhiteNoise() -> Float {
        return Float.random(in: -1.0...1.0)
    }
    
    static private func generatePinkNoise(state: AudioState) -> Float {
        let white = Float.random(in: -1.0...1.0)
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
        
        let result = (state.pinkRunningSum + white) / Float(state.pinkRows.count + 1)
        return result * 3.5
    }
    
    static private func generateBrownNoise(state: AudioState) -> Float {
        let white = Float.random(in: -1.0...1.0)
        state.brownLastOutput = (state.brownLastOutput + (0.02 * white)) / 1.02
        return state.brownLastOutput * 3.5
    }
    
    static private func generateRainNoise(state: AudioState, sampleRate: Float) -> Float {
        // Multi-Layer Rain Algorithm
        
        // 1. RUMBLE: Deep Low-Frequency (Distant)
        // Pink Noise -> LPF (300Hz)
        let pink = generatePinkNoise(state: state)
        let rumbleCoeff: Float = 0.05 // Aggressive LPF
        state.rainRumbleLP = state.rainRumbleLP + rumbleCoeff * (pink - state.rainRumbleLP)
        
        // 2. HISS: Mid-Frequency (Texture)
        // White Noise -> Bandpass (200Hz - 1000Hz)
        // Implemented as LPF (1000Hz) -> HPF (200Hz)
        let white = generateWhiteNoise()
        let hissLPCoeff: Float = 0.15 // ~1000Hz
        let hissHPCoeff: Float = 0.03 // ~200Hz
        
        state.rainHissLP = state.rainHissLP + hissLPCoeff * (white - state.rainHissLP)
        let bandPassedHiss = state.rainHissLP - state.rainHissHP
        state.rainHissHP = state.rainHissHP + hissHPCoeff * (bandPassedHiss - state.rainHissHP)
        
        // 3. DROPLETS: Occasional High-Frequency Impacts
        // Random impulses -> Short Decay -> Low volume
        let dropProb: Float = 0.0003 // Low probability per sample
        var droplet: Float = 0.0
        
        if Float.random(in: 0.0...1.0) < dropProb {
            state.rainDropletFilter = Float.random(in: 0.3...0.6)
        }
        state.rainDropletFilter *= 0.9 // Short decay
        droplet = state.rainDropletFilter * generateWhiteNoise() * 0.5
        
        // 4. PRECIPITATION LFO: Wind Gusts
        state.rainLFOPhase += 0.3 * 2.0 * .pi / sampleRate // Slow modulation
        if state.rainLFOPhase > 2.0 * .pi { state.rainLFOPhase -= 2.0 * .pi }
        let lfo = 0.8 + 0.2 * sin(state.rainLFOPhase)
        
        // MIX
        // Rumble is dominant (warmth). Hiss is background. Droplets are subtle.
        let output = (state.rainRumbleLP * 5.0 * 0.70) +    // Rumble (Boosted because LPF attenuates power)
                     (bandPassedHiss * 0.20) +              // Hiss (Quiet)
                     (droplet * 0.10)                       // Droplets
        
        return output * lfo * 2.0 // Master gain
    }
    
    static private func generateCampfireNoise(state: AudioState, sampleRate: Float) -> Float {
        // === LFO ===
        state.fireLFOPhase += 0.2 * 2.0 * .pi / sampleRate
        if state.fireLFOPhase > 2.0 * .pi { state.fireLFOPhase -= 2.0 * .pi }
        state.fireIntensity = 1.0 + 0.15 * sin(state.fireLFOPhase)
        
        // === Rumble ===
        let w1 = Float.random(in: -1.0...1.0)
        let rumbleCoeff = 0.95 + state.cfRumbleSmooth * 0.049
        state.fireRumble = state.fireRumble * rumbleCoeff + w1 * (1.0 - rumbleCoeff)
        let rumble = state.fireRumble * 3.5 * state.fireIntensity
        
        // === Texture ===
        let noise = Float.random(in: -1.0...1.0)
        let squared = noise * abs(noise)
        let texCoeff = 0.4 + state.cfTextureSmooth * 0.59
        state.fireCrackleLP = state.fireCrackleLP * texCoeff + squared * (1.0 - texCoeff)
        let texture = state.fireCrackleLP * (0.8 + 0.2 * state.fireIntensity)
        
        // === Sizzle ===
        let sizzleRaw = (noise - state.fireCrackleLP) * 0.5
        let sizzle = sizzleRaw * max(0, state.fireIntensity - 0.8)
        
        // === Pops ===
        var impulse: Float = 0.0
        let woodyRate = state.cfWoodyDensity * 10.0
        
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
        let loOut = impulse * 0.4 + 2.0 * effRLo * cos(2.0 * .pi * loFreq / sampleRate) * state.resLo1 - effRLo * effRLo * state.resLo2
        state.resLo2 = state.resLo1
        state.resLo1 = loOut
        
        let midFreq = state.cfFreqMid * state.freqRandMid
        let midOut = impulse * 0.5 + 2.0 * effRMid * cos(2.0 * .pi * midFreq / sampleRate) * state.resMid1 - effRMid * effRMid * state.resMid2
        state.resMid2 = state.resMid1
        state.resMid1 = midOut
        
        let hiFreq = state.cfFreqHi * state.freqRandHi
        let hiOut = impulse * 0.3 + 2.0 * effRHi * cos(2.0 * .pi * hiFreq / sampleRate) * state.resHi1 - effRHi * effRHi * state.resHi2
        state.resHi2 = state.resHi1
        state.resHi1 = hiOut
        
        let woodyPop = loOut * 0.35 + midOut * 0.4 + hiOut * 0.25
        
        // === Mix ===
        return rumble * state.cfRumbleMix + texture * state.cfTextureMix + sizzle * (state.cfTextureMix * 0.5) + woodyPop * state.cfWoodyLevel + state.sharpSnap(sampleRate: sampleRate) * state.cfSnapLevel
    }
}

extension AudioState {
    func sharpSnap(sampleRate: Float) -> Float {
        let snapRate = cfSnapDensity * 5.0
        let snapProb = snapRate / sampleRate
        if Float.random(in: 0.0...1.0) < snapProb {
            return Float.random(in: 0.4...0.8) * (Bool.random() ? 1.0 : -1.0)
        }
        return 0.0
    }
}
