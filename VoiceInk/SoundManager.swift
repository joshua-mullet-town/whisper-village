import Foundation
import AVFoundation
import AppKit
import SwiftUI
import os

private let soundLogger = Logger(subsystem: "town.mullet.WhisperVillage", category: "SoundManager")

/// Available sounds for recording feedback
enum SoundOption: String, CaseIterable, Identifiable {
    case pop = "pop"
    case tink = "tink"
    case bottle = "bottle"
    case glass = "glass"
    case ping = "ping"
    case purr = "purr"
    case morse = "morse"
    case hero = "hero"
    case funk = "funk"
    case submarine = "submarine"
    case originalStart = "originalStart"
    case originalStop = "originalStop"
    case originalEsc = "originalEsc"
    case none = "none"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pop: return "Pop"
        case .tink: return "Tink"
        case .bottle: return "Bottle"
        case .glass: return "Glass"
        case .ping: return "Ping"
        case .purr: return "Purr"
        case .morse: return "Morse"
        case .hero: return "Hero"
        case .funk: return "Funk"
        case .submarine: return "Submarine"
        case .originalStart: return "Original Start"
        case .originalStop: return "Original Stop"
        case .originalEsc: return "Original Esc"
        case .none: return "Silent"
        }
    }

    /// System sound name (nil for bundled sounds)
    var systemSoundName: String? {
        switch self {
        case .pop: return "Pop"
        case .tink: return "Tink"
        case .bottle: return "Bottle"
        case .glass: return "Glass"
        case .ping: return "Ping"
        case .purr: return "Purr"
        case .morse: return "Morse"
        case .hero: return "Hero"
        case .funk: return "Funk"
        case .submarine: return "Submarine"
        case .originalStart, .originalStop, .originalEsc, .none: return nil
        }
    }

    /// Which bundled sound to use (if applicable)
    var bundledSoundType: BundledSoundType? {
        switch self {
        case .originalStart: return .start
        case .originalStop: return .stop
        case .originalEsc: return .esc
        default: return nil
        }
    }

    enum BundledSoundType {
        case start, stop, esc
    }

    /// Sounds suitable for each event type (filtered list)
    static var forStart: [SoundOption] {
        [.pop, .tink, .bottle, .glass, .ping, .morse, .hero, .funk, .originalStart, .none]
    }

    static var forStop: [SoundOption] {
        [.pop, .tink, .bottle, .glass, .ping, .purr, .morse, .submarine, .originalStop, .none]
    }

    static var forCancel: [SoundOption] {
        [.pop, .tink, .bottle, .glass, .funk, .morse, .purr, .originalEsc, .none]
    }

    static var forSend: [SoundOption] {
        [.hero, .ping, .submarine, .pop, .tink, .bottle, .glass, .morse, .funk, .none]
    }
}

class SoundManager: ObservableObject {
    static let shared = SoundManager()

    private var bundledStartSound: AVAudioPlayer?
    private var bundledStopSound: AVAudioPlayer?
    private var bundledEscSound: AVAudioPlayer?

    @AppStorage("isSoundFeedbackEnabled") private var isSoundFeedbackEnabled = true

    // Separate settings for each event
    @AppStorage("startSoundOption") private var startSoundRaw = SoundOption.pop.rawValue
    @AppStorage("stopSoundOption") private var stopSoundRaw = SoundOption.tink.rawValue
    @AppStorage("cancelSoundOption") private var cancelSoundRaw = SoundOption.glass.rawValue
    @AppStorage("sendSoundOption") private var sendSoundRaw = SoundOption.hero.rawValue

    var startSoundOption: SoundOption {
        get { SoundOption(rawValue: startSoundRaw) ?? .pop }
        set {
            startSoundRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    var stopSoundOption: SoundOption {
        get { SoundOption(rawValue: stopSoundRaw) ?? .tink }
        set {
            stopSoundRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    var cancelSoundOption: SoundOption {
        get { SoundOption(rawValue: cancelSoundRaw) ?? .glass }
        set {
            cancelSoundRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    var sendSoundOption: SoundOption {
        get { SoundOption(rawValue: sendSoundRaw) ?? .hero }
        set {
            sendSoundRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    private init() {
        setupBundledSounds()
    }

    private func setupBundledSounds() {
        if let startURL = Bundle.main.url(forResource: "recstart", withExtension: "mp3") {
            bundledStartSound = try? AVAudioPlayer(contentsOf: startURL)
            bundledStartSound?.prepareToPlay()
            bundledStartSound?.volume = 0.4
        }
        if let stopURL = Bundle.main.url(forResource: "recstop", withExtension: "mp3") {
            bundledStopSound = try? AVAudioPlayer(contentsOf: stopURL)
            bundledStopSound?.prepareToPlay()
            bundledStopSound?.volume = 0.4
        }
        if let escURL = Bundle.main.url(forResource: "esc", withExtension: "wav") {
            bundledEscSound = try? AVAudioPlayer(contentsOf: escURL)
            bundledEscSound?.prepareToPlay()
            bundledEscSound?.volume = 0.3
        }
    }

    private func playSystemSound(_ name: String, volume: Float = 0.5) {
        // Play on background thread to avoid conflicts with AVAudioEngine on main thread
        DispatchQueue.global(qos: .userInteractive).async {
            if let sound = NSSound(named: NSSound.Name(name)) {
                sound.volume = volume
                let didPlay = sound.play()
                soundLogger.info("🔊 System sound '\(name)' play() returned: \(didPlay)")
            } else {
                soundLogger.error("❌ System sound '\(name)' not found!")
            }
        }
    }

    private func playBundledSound(_ player: AVAudioPlayer?, volume: Float, name: String) {
        guard let player = player else {
            soundLogger.error("❌ Bundled sound player is nil for '\(name)'")
            return
        }
        // Play on background thread to avoid conflicts with AVAudioEngine on main thread
        DispatchQueue.global(qos: .userInteractive).async {
            player.currentTime = 0
            player.volume = volume
            let didPlay = player.play()
            soundLogger.info("🔊 Bundled sound '\(name)' play() returned: \(didPlay)")
            player.prepareToPlay()
        }
    }

    private func playOption(_ option: SoundOption, volume: Float = 0.5, eventType: String) {
        guard option != .none else {
            soundLogger.info("🔇 Sound disabled for \(eventType) (option=none)")
            return
        }

        soundLogger.info("🎵 Playing \(eventType) sound: \(option.displayName)")

        if let systemName = option.systemSoundName {
            playSystemSound(systemName, volume: volume)
        } else if let bundledType = option.bundledSoundType {
            switch bundledType {
            case .start: playBundledSound(bundledStartSound, volume: 0.4, name: "bundledStart")
            case .stop: playBundledSound(bundledStopSound, volume: 0.4, name: "bundledStop")
            case .esc: playBundledSound(bundledEscSound, volume: 0.3, name: "bundledEsc")
            }
        }
    }

    func playStartSound() {
        soundLogger.info("▶️ playStartSound() called, enabled=\(self.isSoundFeedbackEnabled)")
        guard isSoundFeedbackEnabled else { return }
        playOption(startSoundOption, eventType: "START")
    }

    func playStopSound() {
        soundLogger.info("⏹️ playStopSound() called, enabled=\(self.isSoundFeedbackEnabled)")
        guard isSoundFeedbackEnabled else { return }
        playOption(stopSoundOption, eventType: "STOP")
    }

    func playEscSound() {
        soundLogger.info("⏏️ playEscSound() called, enabled=\(self.isSoundFeedbackEnabled)")
        guard isSoundFeedbackEnabled else { return }
        playOption(cancelSoundOption, eventType: "CANCEL")
    }

    func playSendSound() {
        soundLogger.info("📤 playSendSound() called, enabled=\(self.isSoundFeedbackEnabled)")
        guard isSoundFeedbackEnabled else { return }
        playOption(sendSoundOption, eventType: "SEND")
    }

    /// Preview any sound option
    func preview(_ option: SoundOption) {
        playOption(option, eventType: "PREVIEW")
    }

    var isEnabled: Bool {
        get { isSoundFeedbackEnabled }
        set { isSoundFeedbackEnabled = newValue }
    }
} 
