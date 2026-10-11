import AVFoundation
import Combine
import UIKit

// Port of Speech.kt. Android picks the best installed Hebrew voice that works offline and
// speaks at 0.88 (normal) or 0.65 (slow) of the engine's normal rate. iOS voices are on the
// device; the same factors apply to AVSpeechUtteranceDefaultSpeechRate. Without a Hebrew
// voice, `failed` shows the voice notice and Voice settings opens this app's Settings page.
// The success chime after a right answer (iOS only, owner QA ISSUE-001) plays here too, so the
// speech and the chime share one audio session.

@MainActor
final class Speech: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published private(set) var ready = false
    @Published private(set) var failed = false

    private let synthesizer = AVSpeechSynthesizer()
    private var voice: AVSpeechSynthesisVoice?
    /// Resources/success.wav (Scripts/make_sound.py); nil if it cannot be read.
    private var chime: AVAudioPlayer?

    static let normalRate: Float = 0.88
    static let slowRate: Float = 0.65

    override init() {
        super.init()
        synthesizer.delegate = self
        // Lessons play like media (also with the ring switch on silent), as Android's
        // text-to-speech does, and lower other audio only while speaking (or while the success
        // chime plays).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        if let url = Bundle.main.url(forResource: "success", withExtension: "wav") {
            chime = try? AVAudioPlayer(contentsOf: url)
            chime?.delegate = self
        }
        refresh()
    }

    /// Called at launch and whenever the app becomes active again, so a voice installed in
    /// Settings is found on return (Android refreshes in onResume).
    func refresh() {
        let hebrew = AVSpeechSynthesisVoice.speechVoices().filter { candidate in
            let code = candidate.language.lowercased()
            return code.hasPrefix("he") || code.hasPrefix("iw")
        }
        voice = hebrew.max { $0.quality.rawValue < $1.quality.rawValue }
        ready = voice != nil
        failed = !ready
    }

    func say(_ text: String, slow: Bool = false) {
        guard ready, let chosen = voice else {
            failed = true
            return
        }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = chosen
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (slow ? Speech.slowRate : Speech.normalRate)
        try? AVAudioSession.sharedInstance().setActive(true)
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    /// The short success chime after a right answer. It plays through the same session as the
    /// speech, so it mixes with the speech and with other apps' audio, which is lowered only
    /// while it plays.
    func playSuccess() {
        guard let chime = chime else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        chime.currentTime = 0
        chime.play()
    }

    /// iOS has no public link to the speech voice settings; this opens the app's own page in
    /// Settings, from where Accessibility and its spoken content voices are one step away.
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            failed = true
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                Task { @MainActor in self.failed = true }
            }
        }
    }

    /// Ends the audio session once neither the speech nor the chime is playing, so other apps'
    /// audio returns to full volume.
    private func audioEnded() {
        guard !synthesizer.isSpeaking, chime?.isPlaying != true else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.audioEnded() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.audioEnded() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.audioEnded() }
    }
}
