//
//  WhiteNoiseManager.swift
//  PomodoroSwift
//
//  Generates white, pink, or brown noise using AVAudioEngine.
//

import AVFoundation
import Combine

enum NoiseType: String, CaseIterable {
    case white = "white"
    case pink = "pink"
    case brown = "brown"
    case campfire = "campfire"
    
    var displayName: String {
        switch self {
        case .white: return "White Noise"
        case .pink: return "Pink Noise"
        case .brown: return "Brown Noise"
        case .campfire: return "Campfire 🔥"
        }
    }
}

class WhiteNoiseManager: ObservableObject {
    @Published var isPlaying = false
    
    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    
    private var noiseType: NoiseType = .white
    private var volume: Float = 0.3
    
    // For fade in/out
    private var targetVolume: Float = 0.0
    private var currentVolume: Float = 0.0
    private let fadeSpeed: Float = 0.002 // Per-sample fade increment
    
    // Pink noise filter state (Voss-McCartney algorithm approximation)
    private var pinkRows: [Float] = Array(repeating: 0.0, count: 16)
    private var pinkRunningSum: Float = 0.0
    private var pinkIndex: Int = 0
    
    // Brown noise filter state
    private var brownLastOutput: Float = 0.0
    
    // Campfire state (Andy Farnell "Designing Sound" inspired)
    private var fireRumble: Float = 0.0
    private var fireCrackleLP: Float = 0.0
    // Multi-band resonators: low thud, mid crack, high snap
    private var resLo1: Float = 0.0, resLo2: Float = 0.0
    private var resMid1: Float = 0.0, resMid2: Float = 0.0
    private var resHi1: Float = 0.0, resHi2: Float = 0.0
    // Randomized filters per impulse (to avoid static ringing)
    private var resRandLo: Float = 0.0
    private var resRandMid: Float = 0.0
    private var resRandHi: Float = 0.0
    private var freqRandLo: Float = 1.0
    private var freqRandMid: Float = 1.0
    private var freqRandHi: Float = 1.0
    
    // Breathing mechanism (LFO)
    private var fireLFOPhase: Float = 0.0
    private var fireIntensity: Float = 1.0
    
    // Burst mechanism: occasional rapid-fire pops
    private var burstCountdown: Float = 0.0
    private var burstRemaining: Int = 0
    
    // Campfire tuning parameters (set from Settings)
    private var cfRumbleMix: Float = 0.4
    private var cfTextureMix: Float = 0.3
    private var cfWoodyDensity: Float = 0.3
    private var cfWoodyLevel: Float = 0.5
    private var cfSnapDensity: Float = 0.3
    private var cfSnapLevel: Float = 0.35
    private var cfRumbleSmooth: Float = 0.95
    private var cfTextureSmooth: Float = 0.6
    private var cfFreqLo: Float = 300.0
    private var cfFreqMid: Float = 900.0
    private var cfFreqHi: Float = 2500.0
    private var cfResonance: Float = 0.5
    private var cfBurstProb: Float = 0.12
    
    func play() {
        guard !isPlaying else { return }
        
        setupEngine()
        
        targetVolume = volume
        
        do {
            try audioEngine?.start()
            isPlaying = true
        } catch {
            print("WhiteNoiseManager: Failed to start audio engine: \(error)")
        }
    }
    
    func stop() {
        guard isPlaying else { return }
        
        // Fade out then stop
        targetVolume = 0.0
        
        // Give time for fade out, then fully stop
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.audioEngine?.stop()
            self?.audioEngine = nil
            self?.sourceNode = nil
            self?.isPlaying = false
            self?.currentVolume = 0.0
            // Reset filter states
            self?.pinkRows = Array(repeating: 0.0, count: 16)
            self?.pinkRunningSum = 0.0
            self?.pinkIndex = 0
            self?.brownLastOutput = 0.0
            self?.fireRumble = 0.0
            self?.fireCrackleLP = 0.0
            self?.resLo1 = 0.0; self?.resLo2 = 0.0
            self?.resMid1 = 0.0; self?.resMid2 = 0.0
            self?.resHi1 = 0.0; self?.resHi2 = 0.0
            self?.burstCountdown = 0.0
            self?.burstRemaining = 0
        }
    }
    
    func setVolume(_ newVolume: Double) {
        volume = Float(newVolume)
        if isPlaying {
            targetVolume = volume
        }
    }
    
    func setCampfireParams(rumble: Double, texture: Double, woodyDensity: Double, woodyLevel: Double, snapDensity: Double, snapLevel: Double, rumbleSmooth: Double, textureSmooth: Double, freqLo: Double, freqMid: Double, freqHi: Double, resonance: Double, burstProb: Double) {
        cfRumbleMix = Float(rumble)
        cfTextureMix = Float(texture)
        cfWoodyDensity = Float(woodyDensity)
        cfWoodyLevel = Float(woodyLevel)
        cfSnapDensity = Float(snapDensity)
        cfSnapLevel = Float(snapLevel)
        cfRumbleSmooth = Float(rumbleSmooth)
        cfTextureSmooth = Float(textureSmooth)
        cfFreqLo = Float(freqLo)
        cfFreqMid = Float(freqMid)
        cfFreqHi = Float(freqHi)
        cfResonance = Float(resonance)
        cfBurstProb = Float(burstProb)
    }
    
    func setNoiseType(_ type: NoiseType) {
        let wasPlaying = isPlaying
        if wasPlaying {
            audioEngine?.stop()
            audioEngine = nil
            sourceNode = nil
            isPlaying = false
            currentVolume = 0.0
            // Reset filter states
            pinkRows = Array(repeating: 0.0, count: 16)
            pinkRunningSum = 0.0
            pinkIndex = 0
            brownLastOutput = 0.0
            fireRumble = 0.0
            fireCrackleLP = 0.0
            resLo1 = 0.0; resLo2 = 0.0
            resMid1 = 0.0; resMid2 = 0.0
            resHi1 = 0.0; resHi2 = 0.0
            burstCountdown = 0.0
            burstRemaining = 0
            fireLFOPhase = 0.0
            fireIntensity = 1.0
        }
        noiseType = type
        if wasPlaying {
            play()
        }
    }
    
    private func setupEngine() {
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }
        
        let mainMixer = engine.mainMixerNode
        let outputFormat = mainMixer.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        
        sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            
            for frame in 0..<Int(frameCount) {
                // Smooth volume transitions
                if self.currentVolume < self.targetVolume {
                    self.currentVolume = min(self.currentVolume + self.fadeSpeed, self.targetVolume)
                } else if self.currentVolume > self.targetVolume {
                    self.currentVolume = max(self.currentVolume - self.fadeSpeed, self.targetVolume)
                }
                
                let sample: Float
                switch self.noiseType {
                case .white:
                    sample = self.generateWhiteNoise()
                case .pink:
                    sample = self.generatePinkNoise()
                case .brown:
                    sample = self.generateBrownNoise()
                case .campfire:
                    sample = self.generateCampfireNoise(sampleRate: Float(sampleRate))
                }
                
                let scaledSample = sample * self.currentVolume
                
                for buffer in ablPointer {
                    let buf = UnsafeMutableBufferPointer<Float>(buffer)
                    buf[frame] = scaledSample
                }
            }
            
            return noErr
        }
        
        guard let sourceNode = sourceNode else { return }
        
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: mainMixer, format: format)
        
        engine.prepare()
    }
    
    // MARK: - Noise Generation Algorithms
    
    private func generateWhiteNoise() -> Float {
        return Float.random(in: -1.0...1.0)
    }
    
    /// Voss-McCartney algorithm for pink noise (-3 dB/octave)
    private func generatePinkNoise() -> Float {
        let white = Float.random(in: -1.0...1.0)
        
        pinkIndex = (pinkIndex + 1) % (pinkRows.count)
        
        // Find the number of trailing zeros to determine which row to update
        var k = pinkIndex
        var numZeros = 0
        if k > 0 {
            while k & 1 == 0 {
                numZeros += 1
                k >>= 1
            }
        }
        
        if numZeros < pinkRows.count {
            pinkRunningSum -= pinkRows[numZeros]
            let newRandom = Float.random(in: -1.0...1.0)
            pinkRunningSum += newRandom
            pinkRows[numZeros] = newRandom
        }
        
        // Normalize: sum of rows + current white, divided by (count + 1) for scaling
        let result = (pinkRunningSum + white) / Float(pinkRows.count + 1)
        return result * 3.5 // Boost to roughly match white noise loudness
    }
    
    /// Brown noise (Brownian / red noise, -6 dB/octave)
    private func generateBrownNoise() -> Float {
        let white = Float.random(in: -1.0...1.0)
        brownLastOutput = (brownLastOutput + (0.02 * white)) / 1.02
        return brownLastOutput * 3.5 // Scale up to useful amplitude
    }
    
    /// Campfire — Farnell-style with "Breathing" and Organic Randomization
    private func generateCampfireNoise(sampleRate: Float) -> Float {
        // === 0. Breathing Mechanism (LFO) ===
        // Slow modulation (0.15 - 0.2 Hz) to simulate fire intensity changes
        fireLFOPhase += 0.2 * 2.0 * .pi / sampleRate
        if fireLFOPhase > 2.0 * .pi { fireLFOPhase -= 2.0 * .pi }
        // Intensity oscillates between 0.85 and 1.15
        fireIntensity = 1.0 + 0.15 * sin(fireLFOPhase)
        
        // === Layer 1: Deep warm rumble (Modulated) ===
        let w1 = Float.random(in: -1.0...1.0)
        // Smoothness: 0=raw noise, 1=ultra smooth. Maps to filter coeff 0.95-0.999 (Deep Bass)
        let rumbleCoeff = 0.95 + cfRumbleSmooth * 0.049
        fireRumble = fireRumble * rumbleCoeff + w1 * (1.0 - rumbleCoeff)
        // Rumble gets louder when fire is intense
        let rumble = fireRumble * 3.5 * fireIntensity // Boosted gain to compensate for heavy filtering
        
        // === Layer 2: Squared noise texture (Modulated) ===
        let noise = Float.random(in: -1.0...1.0)
        let squared = noise * abs(noise)
        // Texture smoothness: 0=raw, 1=smooth. Maps to 0.4-0.99 (Warmer)
        let texCoeff = 0.4 + cfTextureSmooth * 0.59
        fireCrackleLP = fireCrackleLP * texCoeff + squared * (1.0 - texCoeff)
        // Texture breathing is subtle
        let texture = fireCrackleLP * (0.8 + 0.2 * fireIntensity)
        
        // === Layer 2b: Hiss/Sizzle (Track Intensity) ===
        // High-pass filtered noise that follows intensity
        let sizzleRaw = (noise - fireCrackleLP) * 0.5
        let sizzle = sizzleRaw * max(0, fireIntensity - 0.8) // Only audible during flare-ups
        
        // === Layer 3: Dust impulses with burst mechanism (woody pops) ===
        var impulse: Float = 0.0
        let woodyRate = cfWoodyDensity * 10.0
        
        // Check for new impulse trigger
        var triggered = false
        
        if burstRemaining > 0 {
            burstCountdown -= 1.0
            if burstCountdown <= 0 {
                impulse = Float.random(in: 0.2...0.7) * (Bool.random() ? 1.0 : -1.0)
                burstRemaining -= 1
                burstCountdown = Float.random(in: 600...2000)
                triggered = true
            }
        } else {
            let dustProb = woodyRate / sampleRate
            if Float.random(in: 0.0...1.0) < dustProb {
                impulse = Float.random(in: 0.3...0.9) * (Bool.random() ? 1.0 : -1.0)
                triggered = true
                
                if Float.random(in: 0.0...1.0) < cfBurstProb {
                    burstRemaining = Int.random(in: 2...3)
                    burstCountdown = Float.random(in: 500...1500)
                }
            }
        }
        
        // If triggered, randomize filter parameters for this specific pop
        if triggered {
            // Randomize resonance (±0.05)
            let rBase = 0.80 + cfResonance * 0.19
            resRandLo = max(0.8, min(0.99, rBase + Float.random(in: -0.03...0.03)))
            resRandMid = max(0.8, min(0.99, rBase + Float.random(in: -0.05...0.05)))
            resRandHi = max(0.8, min(0.99, rBase + Float.random(in: -0.02...0.02)))
            
            // Randomize frequency (±15%) for organic timber varation
            freqRandLo = Float.random(in: 0.85...1.15)
            freqRandMid = Float.random(in: 0.85...1.15)
            freqRandHi = Float.random(in: 0.85...1.15)
        }
        
        // Use last randomized values (or defaults if never triggered)
        let effRLo = resRandLo == 0 ? (0.80 + cfResonance * 0.19) : resRandLo
        let effRMid = resRandMid == 0 ? (0.80 + cfResonance * 0.19) : resRandMid
        let effRHi = resRandHi == 0 ? (0.80 + cfResonance * 0.19) : resRandHi
        
        // === Layer 4: Sharp snaps ===
        var sharpSnap: Float = 0.0
        let snapRate = cfSnapDensity * 5.0
        let snapProb = snapRate / sampleRate
        if Float.random(in: 0.0...1.0) < snapProb {
            sharpSnap = Float.random(in: 0.4...0.8) * (Bool.random() ? 1.0 : -1.0)
        }
        
        // === Multi-band resonant filters ===
        let loFreq = cfFreqLo * freqRandLo
        let loOut = impulse * 0.4 + 2.0 * effRLo * cos(2.0 * .pi * loFreq / sampleRate) * resLo1 - effRLo * effRLo * resLo2
        resLo2 = resLo1
        resLo1 = loOut
        
        let midFreq = cfFreqMid * freqRandMid
        let midOut = impulse * 0.5 + 2.0 * effRMid * cos(2.0 * .pi * midFreq / sampleRate) * resMid1 - effRMid * effRMid * resMid2
        resMid2 = resMid1
        resMid1 = midOut
        
        let hiFreq = cfFreqHi * freqRandHi
        let hiOut = impulse * 0.3 + 2.0 * effRHi * cos(2.0 * .pi * hiFreq / sampleRate) * resHi1 - effRHi * effRHi * resHi2
        resHi2 = resHi1
        resHi1 = hiOut
        
        let woodyPop = loOut * 0.35 + midOut * 0.4 + hiOut * 0.25
        
        // === Mix with tunable levels ===
        return rumble * cfRumbleMix + texture * cfTextureMix + sizzle * (cfTextureMix * 0.5) + woodyPop * cfWoodyLevel + sharpSnap * cfSnapLevel
    }
}
