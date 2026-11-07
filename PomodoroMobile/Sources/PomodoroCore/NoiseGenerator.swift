import Foundation

// Signal layers and resonators are ported from the desktop WhiteNoiseManager.
// Each generation owns its filter state and seeded random source.
private final class NoiseState {
    var noiseType: AmbientSound = .white

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
    var rng: UInt64 = 42
    func random(in range: ClosedRange<Float>) -> Float {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        let unit = Float(rng >> 40) / Float(1 << 24)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
    func randomBool() -> Bool { random(in: 0...1) < 0.5 }
    func randomInt(in range: ClosedRange<Int>) -> Int {
        min(range.upperBound, range.lowerBound + Int(random(in: 0...1) * Float(range.upperBound - range.lowerBound + 1)))
    }
}

public enum NoiseGenerator {
    public static func samples(sound: AmbientSound, count: Int, seed: UInt64 = 42,
                               campfire: CampfireParameters = CampfireParameters(), sampleRate: Float = 48_000) -> [Float] {
        guard count > 0, count <= 11_520_000 else { return [] }
        guard sampleRate.isFinite, sampleRate >= 16_000 else { return [] }
        let state = NoiseState()
        state.noiseType = sound; state.rng = seed
        let p = campfire.normalized
        state.cfRumbleMix = Float(p.rumble); state.cfTextureMix = Float(p.texture)
        state.cfWoodyDensity = Float(p.woodyDensity); state.cfWoodyLevel = Float(p.woodyLevel)
        state.cfSnapDensity = Float(p.snapDensity); state.cfSnapLevel = Float(p.snapLevel)
        state.cfRumbleSmooth = Float(p.rumbleSmooth); state.cfTextureSmooth = Float(p.textureSmooth)
        state.cfFreqLo = Float(p.freqLo); state.cfFreqMid = Float(p.freqMid); state.cfFreqHi = Float(p.freqHi)
        state.cfResonance = Float(p.resonance); state.cfBurstProb = Float(p.burstProb)
        var output = [Float](repeating: 0, count: count)
        for index in output.indices {
            if index.isMultiple(of: 4096) && Task.isCancelled { return [] }
            let sample = generateSample(state: state, sampleRate: sampleRate)
            output[index] = sample.isFinite ? min(0.95, max(-0.95, sample)) : 0
        }
        let blend = min(2048, count / 4)
        if blend > 1 {
            for index in 0..<blend {
                let mix = Float(index) / Float(blend - 1)
                output[count - blend + index] = output[count - blend + index] * (1 - mix) + output[0] * mix
            }
        }
        return output
    }

    static private func generateSample(state: NoiseState, sampleRate: Float) -> Float {
        switch state.noiseType {
        case .none: return 0
        case .white:
            return generateWhiteNoise(state: state)
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

    static private func generateWhiteNoise(state: NoiseState) -> Float {
        return state.random(in: -1.0...1.0)
    }

    static private func generatePinkNoise(state: NoiseState) -> Float {
        let white = state.random(in: -1.0...1.0)
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
            let newRandom = state.random(in: -1.0...1.0)
            state.pinkRunningSum += newRandom
            state.pinkRows[numZeros] = newRandom
        }

        let result = (state.pinkRunningSum + white) / Float(state.pinkRows.count + 1)
        return result * 3.5
    }

    static private func generateBrownNoise(state: NoiseState) -> Float {
        let white = state.random(in: -1.0...1.0)
        state.brownLastOutput = (state.brownLastOutput + (0.02 * white)) / 1.02
        return state.brownLastOutput * 3.5
    }

    static private func generateRainNoise(state: NoiseState, sampleRate: Float) -> Float {
        // Multi-Layer Rain Algorithm

        // 1. RUMBLE: Deep Low-Frequency (Distant)
        // Pink Noise -> LPF (300Hz)
        let pink = generatePinkNoise(state: state)
        let rumbleCoeff: Float = 0.05 // Aggressive LPF
        state.rainRumbleLP = state.rainRumbleLP + rumbleCoeff * (pink - state.rainRumbleLP)

        // 2. HISS: Mid-Frequency (Texture)
        // White Noise -> Bandpass (200Hz - 1000Hz)
        // Implemented as LPF (1000Hz) -> HPF (200Hz)
        let white = generateWhiteNoise(state: state)
        let hissLPCoeff: Float = 0.15 // ~1000Hz
        let hissHPCoeff: Float = 0.03 // ~200Hz

        state.rainHissLP = state.rainHissLP + hissLPCoeff * (white - state.rainHissLP)
        let bandPassedHiss = state.rainHissLP - state.rainHissHP
        state.rainHissHP = state.rainHissHP + hissHPCoeff * (bandPassedHiss - state.rainHissHP)

        // 3. DROPLETS: Occasional High-Frequency Impacts
        // Random impulses -> Short Decay -> Low volume
        let dropProb: Float = 0.0003 // Low probability per sample
        var droplet: Float = 0.0

        if state.random(in: 0.0...1.0) < dropProb {
            state.rainDropletFilter = state.random(in: 0.3...0.6)
        }
        state.rainDropletFilter *= 0.9 // Short decay
        droplet = state.rainDropletFilter * generateWhiteNoise(state: state) * 0.5

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

    static private func generateCampfireNoise(state: NoiseState, sampleRate: Float) -> Float {
        // === LFO ===
        state.fireLFOPhase += 0.2 * 2.0 * .pi / sampleRate
        if state.fireLFOPhase > 2.0 * .pi { state.fireLFOPhase -= 2.0 * .pi }
        state.fireIntensity = 1.0 + 0.15 * sin(state.fireLFOPhase)

        // === Rumble ===
        let w1 = state.random(in: -1.0...1.0)
        let rumbleCoeff = 0.95 + state.cfRumbleSmooth * 0.049
        state.fireRumble = state.fireRumble * rumbleCoeff + w1 * (1.0 - rumbleCoeff)
        let rumble = state.fireRumble * 3.5 * state.fireIntensity

        // === Texture ===
        let noise = state.random(in: -1.0...1.0)
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
                impulse = state.random(in: 0.2...0.7) * (state.randomBool() ? 1.0 : -1.0)
                state.burstRemaining -= 1
                state.burstCountdown = state.random(in: 600...2000)
                triggered = true
            }
        } else {
            let dustProb = woodyRate / sampleRate
            if state.random(in: 0.0...1.0) < dustProb {
                impulse = state.random(in: 0.3...0.9) * (state.randomBool() ? 1.0 : -1.0)
                triggered = true
                if state.random(in: 0.0...1.0) < state.cfBurstProb {
                    state.burstRemaining = state.randomInt(in: 2...3)
                    state.burstCountdown = state.random(in: 500...1500)
                }
            }
        }

        if triggered {
            let rBase = 0.80 + state.cfResonance * 0.19
            state.resRandLo = max(0.8, min(0.99, rBase + state.random(in: -0.03...0.03)))
            state.resRandMid = max(0.8, min(0.99, rBase + state.random(in: -0.05...0.05)))
            state.resRandHi = max(0.8, min(0.99, rBase + state.random(in: -0.02...0.02)))

            state.freqRandLo = state.random(in: 0.85...1.15)
            state.freqRandMid = state.random(in: 0.85...1.15)
            state.freqRandHi = state.random(in: 0.85...1.15)
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

private extension NoiseState {
    func sharpSnap(sampleRate: Float) -> Float {
        let snapRate = cfSnapDensity * 5.0
        let snapProb = snapRate / sampleRate
        if random(in: 0.0...1.0) < snapProb {
            return random(in: 0.4...0.8) * (randomBool() ? 1.0 : -1.0)
        }
        return 0.0
    }
}
