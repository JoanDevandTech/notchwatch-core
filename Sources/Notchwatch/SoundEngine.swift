import AVFoundation
import Foundation
import NotchwatchCore
import os

/// Sonidos propios sintetizados al vuelo (sin ficheros de audio):
/// - `soft`: campanita de dos notas para incidencias baja/media.
/// - `urgent`: tres notas más brillantes y rápidas para alta/urgente.
@MainActor
final class SoundEngine {
    private struct Note {
        let frequency: Double
        let start: Double
        let duration: Double
        let decay: Double
        let gain: Double
    }

    private static let softNotes = [
        Note(frequency: 1_046.50, start: 0.00, duration: 0.95, decay: 5.0, gain: 0.30),
        Note(frequency: 1_567.98, start: 0.14, duration: 1.10, decay: 4.2, gain: 0.26),
    ]

    private static let urgentNotes = [
        Note(frequency: 880.00, start: 0.00, duration: 0.40, decay: 8.0, gain: 0.34),
        Note(frequency: 1_174.66, start: 0.13, duration: 0.40, decay: 8.0, gain: 0.34),
        Note(frequency: 1_760.00, start: 0.26, duration: 0.75, decay: 5.5, gain: 0.32),
    ]

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private var buffers: [SoundKind: AVAudioPCMBuffer] = [:]
    private var isConfigured = false
    private let log = Logger(subsystem: "com.joandev.notchwatch", category: "sound")

    func play(_ kind: SoundKind) {
        guard let buffer = buffer(for: kind) else { return }
        do {
            try configureIfNeeded()
            if !engine.isRunning {
                try engine.start()
            }
            player.stop()
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            player.play()
        } catch {
            log.error("No se pudo reproducir el sonido: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Genera los dos sonidos sin reproducirlos (lo usa el self-test de la CI).
    func prepareBuffers() -> Bool {
        buffer(for: .soft) != nil && buffer(for: .urgent) != nil
    }

    private func configureIfNeeded() throws {
        guard !isConfigured, let format else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9
        engine.prepare()
        isConfigured = true
    }

    private func buffer(for kind: SoundKind) -> AVAudioPCMBuffer? {
        if let cached = buffers[kind] { return cached }
        guard let format else { return nil }
        let notes = kind == .soft ? SoundEngine.softNotes : SoundEngine.urgentNotes
        let sampleRate = format.sampleRate
        let total = notes.map { $0.start + $0.duration }.max() ?? 1
        let frameCount = AVAudioFrameCount(total * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frameCount
        let frames = Int(frameCount)
        for index in 0..<frames {
            channel[index] = 0
        }
        for note in notes {
            let startFrame = Int(note.start * sampleRate)
            let length = Int(note.duration * sampleRate)
            for offset in 0..<length {
                let index = startFrame + offset
                if index >= frames { break }
                let time = Double(offset) / sampleRate
                let attack = min(1, time / 0.006)
                let envelope = attack * exp(-time * note.decay)
                let phase = 2 * Double.pi * note.frequency * time
                // Fundamental + armónicos suaves que se apagan antes: timbre de campana.
                var sample = sin(phase)
                sample += 0.35 * sin(phase * 2) * exp(-time * note.decay * 1.6)
                sample += 0.12 * sin(phase * 3.01) * exp(-time * note.decay * 2.4)
                channel[index] += Float(sample * envelope * note.gain)
            }
        }
        var peak: Float = 0
        for index in 0..<frames {
            peak = max(peak, abs(channel[index]))
        }
        if peak > 0.95 {
            let scale = 0.95 / peak
            for index in 0..<frames {
                channel[index] *= scale
            }
        }
        buffers[kind] = buffer
        return buffer
    }
}
