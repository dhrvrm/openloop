import Foundation
import WhisperKit

enum UtteranceAudioChunker {
    static func ranges(
        in audio: [Float],
        sampleRate: Int = WhisperKit.sampleRate,
        maximumInternalSilence: TimeInterval = 0.45,
        minimumSpeechDuration: TimeInterval = 0.35,
        padding: TimeInterval = 0.15
    ) -> [Range<Int>] {
        guard !audio.isEmpty, sampleRate > 0 else { return [] }
        let vad = EnergyVAD(
            sampleRate: sampleRate,
            frameLength: 0.05,
            energyThreshold: 0.005
        )
        let active = vad.calculateActiveChunks(in: audio)
        guard !active.isEmpty else { return [] }

        let maximumGap = Int(maximumInternalSilence * Double(sampleRate))
        var merged: [Range<Int>] = []
        for chunk in active {
            let range = chunk.startIndex..<chunk.endIndex
            if let last = merged.last, range.lowerBound - last.upperBound <= maximumGap {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }

        let minimumSamples = Int(minimumSpeechDuration * Double(sampleRate))
        let paddingSamples = Int(padding * Double(sampleRate))
        return merged.compactMap { range -> Range<Int>? in
            guard range.count >= minimumSamples else { return nil }
            return max(0, range.lowerBound - paddingSamples)..<min(
                audio.count,
                range.upperBound + paddingSamples
            )
        }
    }
}
