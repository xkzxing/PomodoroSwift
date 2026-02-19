//
//  WhiteNoiseManager.swift
//  PomodoroSwift
//
//  Generates white, pink, brown, campfire, or "cozy" rain noise using AVAudioEngine.
//  Uses a Hybrid "Source -> Player" Strategy for minimum energy:
//  1. AVAudioSourceNode (Real-Time): Provides instant start and parameter feedback.
//     - Kept alive but disconnected when not needed to save energy.
//  2. AVAudioPlayerNode (Buffer Loop): Provides lowest possible energy usage (native C++ loop).
//  3. Hot Swap: On parameter change, reconnect SourceNode (RT) -> Generate New Buffer -> Switch to PlayerNode.
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
    private var sourceNode: AVAudioSourceNode?    // Real-Time (Interactive / Loading)
    private var playerNode: AVAudioPlayerNode?    // Efficient Loop (Steady State)
    
    // Real-Time State (Held here to update params live)
    private var rtState: AudioState?
    
    // Generation Control
    private var currentGenerationID: Int = 0
    private let generationLock = NSLock()
    
    // Caching
    private var cachedBuffer: AVAudioPCMBuffer?
    private var cachedNoiseType: NoiseType = .white
    
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
        
        setupEngine()
        
        do {
            try audioEngine?.start()
            isPlaying = true
            
            // Start Logic
            if let cache = cachedBuffer, cachedNoiseType == currentNoiseType {
                // Hot Start: Reuse Cache
                startPlayerNode(with: cache)
            } else {
                // Cold Start: RT -> Gen -> Player
                startSourceNode()
                dispatchBufferGeneration()
            }
        } catch {
            print("WhiteNoiseManager: Failed to start audio engine: \(error)")
        }
    }
    
    func stop() {
        guard isPlaying else { return }
        
        // Fade out
        if let mixer = audioEngine?.mainMixerNode {
            fadeVolume(mixer: mixer, to: 0.0, duration: 0.5)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.playerNode?.stop()
            self?.audioEngine?.stop()
            self?.audioEngine = nil
            self?.sourceNode = nil
            self?.playerNode = nil
            self?.rtState = nil
            self?.isPlaying = false
        }
    }
    
    func setVolume(_ newVolume: Double) {
        currentVolume = Float(newVolume)
        if isPlaying, let mixer = audioEngine?.mainMixerNode {
            mixer.outputVolume = currentVolume
        }
    }
    
    func setCampfireParams(rumble: Double, texture: Double, woodyDensity: Double, woodyLevel: Double, snapDensity: Double, snapLevel: Double, rumbleSmooth: Double, textureSmooth: Double, freqLo: Double, freqMid: Double, freqHi: Double, resonance: Double, burstProb: Double) {
        
        // Update local params
        cfParams = (
            Float(rumble), Float(texture), Float(woodyDensity), Float(woodyLevel),
            Float(snapDensity), Float(snapLevel), Float(rumbleSmooth), Float(textureSmooth),
            Float(freqLo), Float(freqMid), Float(freqHi), Float(resonance), Float(burstProb)
        )
        
        // Invalidate cache
        cachedBuffer = nil
        
        // If playing, apply update live
        if isPlaying {
            // 1. Update RT State
            if let state = rtState {
                applyParams(to: state)
            }
            
            // 2. Switch to SourceNode (Instant Feedback)
            startSourceNode()
            
            // 3. Increment ID to cancel/supersede pending generations
            incrementGenerationID()
            
            // 4. Dispatch new low-energy buffer generation
            dispatchBufferGeneration()
        }
    }
    
    func setNoiseType(_ type: NoiseType) {
        let wasPlaying = isPlaying
        if wasPlaying {
            currentNoiseType = type
            setVolume(Double(currentVolume)) // Re-apply volume
            
            cachedBuffer = nil
            cachedNoiseType = type
            
            if let state = rtState {
                state.noiseType = type
                // Reset specialized state on switch
                state.rainRumbleLP = 0
                state.rainHissLP = 0
                state.rainHissHP = 0
                state.rainLFOPhase = 0
                applyParams(to: state)
            }
            
            startSourceNode()
            incrementGenerationID()
            dispatchBufferGeneration()
            
        } else {
            currentNoiseType = type
            if type != cachedNoiseType {
                cachedBuffer = nil
                cachedNoiseType = type
            }
        }
    }
    
    // MARK: - Engine Setup
    
    private func setupEngine() {
        let engine = AVAudioEngine()
        audioEngine = engine
        
        let mainMixer = engine.mainMixerNode
        let outputFormat = mainMixer.outputFormat(forBus: 0)
        currentSampleRate = outputFormat.sampleRate
        
        // Set Volume
        mainMixer.outputVolume = currentVolume
        
        // 1. Source Node (RT)
        let format = AVAudioFormat(standardFormatWithSampleRate: currentSampleRate, channels: 1)!
        
        let state = AudioState()
        state.noiseType = currentNoiseType
        applyParams(to: state)
        self.rtState = state
        
        sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sample = WhiteNoiseManager.generateSample(state: state, sampleRate: Float(outputFormat.sampleRate))
                for buffer in ablPointer {
                    let buf = UnsafeMutableBufferPointer<Float>(buffer)
                    buf[frame] = sample
                }
            }
            return noErr
        }
        
        // 2. Player Node (Loop)
        playerNode = AVAudioPlayerNode()
        
        guard let sourceNode = sourceNode, let playerNode = playerNode else { return }
        
        engine.attach(sourceNode)
        engine.attach(playerNode)
        
        // Initial Connection: Connect both. We will detach/disconnect source when not needed.
        engine.connect(sourceNode, to: mainMixer, format: format)
        engine.connect(playerNode, to: mainMixer, format: format)
        
        engine.prepare()
    }
    
    // MARK: - Playback Logic
    
    private func startSourceNode() {
        guard let engine = audioEngine, let src = sourceNode, let mixer = audioEngine?.mainMixerNode else { return }
        
        let internalFormat = AVAudioFormat(standardFormatWithSampleRate: currentSampleRate, channels: 1)!
        
        // Just reconnect.
        engine.disconnectNodeOutput(src)
        engine.connect(src, to: mixer, format: internalFormat)
        
        playerNode?.volume = 0 
        playerNode?.stop() 
    }
    
    private func startPlayerNode(with buffer: AVAudioPCMBuffer) {
        guard let engine = audioEngine, let player = playerNode else { return }
        
        // 1. Schedule Buffer
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        player.volume = 1.0 // Reset volume
        player.play()
        
        // 2. Wait a tiny bit (crossfade simulation), then disconnect SourceNode
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, let src = self.sourceNode else { return }
            if self.playerNode?.isPlaying == true {
                engine.disconnectNodeOutput(src)
            }
        }
    }
    
    // MARK: - Buffer Generation
    
    private func incrementGenerationID() {
        generationLock.lock()
        currentGenerationID += 1
        generationLock.unlock()
    }
    
    private func getGenerationID() -> Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        return currentGenerationID
    }
    
    private func dispatchBufferGeneration() {
        let sr = currentSampleRate
        let type = currentNoiseType
        let genID = getGenerationID()
        
        // Background State (Clone Settings)
        let bgState = AudioState()
        bgState.noiseType = type
        applyParams(to: bgState)
        
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Generate Buffer
            if self.getGenerationID() != genID { return }
            
            guard let buffer = self.generatePCMBuffer(state: bgState, sampleRate: sr, duration: self.loopDuration) else { return }
            
            if self.getGenerationID() != genID { return }
            
            // Update Cache & Switch to Player
            DispatchQueue.main.async {
                // Final check on main thread
                if self.getGenerationID() == genID {
                    self.cachedBuffer = buffer
                    self.cachedNoiseType = type
                    if self.isPlaying {
                        self.startPlayerNode(with: buffer)
                    }
                }
            }
        }
    }
    
    private func generatePCMBuffer(state: AudioState, sampleRate: Double, duration: Double) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!, frameCapacity: frameCount) else { return nil }
        
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        
        for i in 0..<Int(frameCount) {
            channelData[i] = WhiteNoiseManager.generateSample(state: state, sampleRate: Float(sampleRate))
        }
        
        return buffer
    }
    
    // MARK: - Helpers
    
    private func fadeVolume(mixer: AVAudioMixerNode, to endVolume: Float, duration: TimeInterval) {
        let startVolume = mixer.outputVolume
        let steps = 10
        let stepDuration = duration / Double(steps)
        let stepValue = (endVolume - startVolume) / Float(steps)
        
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) {
                mixer.outputVolume = startVolume + stepValue * Float(i)
            }
        }
    }
    
    private func applyParams(to state: AudioState) {
        state.cfRumbleMix = cfParams.rumble
        state.cfTextureMix = cfParams.texture
        state.cfWoodyDensity = cfParams.woodyDensity
        state.cfWoodyLevel = cfParams.woodyLevel
        state.cfSnapDensity = cfParams.snapDensity
        state.cfSnapLevel = cfParams.snapLevel
        state.cfRumbleSmooth = cfParams.rumbleSmooth
        state.cfTextureSmooth = cfParams.textureSmooth
        state.cfFreqLo = cfParams.freqLo
        state.cfFreqMid = cfParams.freqMid
        state.cfFreqHi = cfParams.freqHi
        state.cfResonance = cfParams.resonance
        state.cfBurstProb = cfParams.burstProb
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
