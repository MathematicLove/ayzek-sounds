import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import Combine

/// The playback engine: AVAudioEngine graph (player -> time/pitch -> 10-band EQ -> mixer),
/// Now Playing info, remote commands, interruption/route handling and queue navigation.
final class AudioEngine: ObservableObject {
    enum State { case idle, loaded, playing, paused }
    enum RepeatMode { case off, single, all }

    @Published var currentTrack: Track?
    @Published private(set) var state: State = .idle
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var repeatMode: RepeatMode = .off
    @Published var shuffleEnabled: Bool = false
    @Published var playbackRate: Float = 1.0 {
        didSet { timePitch.rate = playbackRate }
    }

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    let eq = AVAudioUnitEQ(numberOfBands: eqFrequencies.count)

    private var audioFile: AVAudioFile?
    private var timer: Timer?
    private var fileSampleRate: Double = 44100
    private var totalFrames: AVAudioFramePosition = 0
    private var startFrame: AVAudioFramePosition = 0

    private var nowPlayingInfo: [String: Any] = [:]
    private var artworkImage: UIImage?

    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    /// Supplied by the app: how to resolve file URLs and the playback order.
    var libraryProvider: (() -> LibraryStore?)?
    var playOrderProvider: (() -> [Track])?

    private var equalizerCancellable: AnyCancellable?

    init(equalizerStore: EqualizerStore) {
        setupSession()
        setupEngine()
        configureEQBands()
        bindEqualizer(equalizerStore)
        setupTimer()
        setupRemoteCommands()
        observeAudioSession()
        observeAppLifecycle()
    }

    deinit { timer?.invalidate() }

    // MARK: Setup

    private func setupSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            print("AudioSession error: \(error)")
        }
    }

    private func setupEngine() {
        engine.attach(playerNode)
        engine.attach(timePitch)
        engine.attach(eq)
        engine.connect(playerNode, to: timePitch, format: nil)
        engine.connect(timePitch, to: eq, format: nil)
        engine.connect(eq, to: engine.mainMixerNode, format: nil)
        engine.prepare()
        do { try engine.start() } catch { print("Engine start error: \(error)") }
    }

    private func configureEQBands() {
        for (i, band) in eq.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = eqFrequencies[i]
            band.bandwidth = 0.9
            band.gain = 0
            band.bypass = false
        }
    }

    /// Keeps the live AVAudioUnitEQ in sync with the persisted equalizer settings.
    private func bindEqualizer(_ store: EqualizerStore) {
        applyEqualizer(store.state)
        equalizerCancellable = store.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.applyEqualizer(state) }
    }

    private func applyEqualizer(_ state: EqualizerState) {
        eq.bypass = !state.isEnabled
        eq.globalGain = max(-24, min(24, state.preampDB))
        for (i, band) in eq.bands.enumerated() where i < state.bandGains.count {
            band.gain = max(-12, min(12, state.bandGains[i]))
        }
    }

    private func restartEngineIfNeeded() {
        if !engine.isRunning {
            do { try engine.start() } catch { print("Engine restart error: \(error)") }
        }
    }

    private func setupTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self = self, self.state == .playing,
                  let nodeTime = self.playerNode.lastRenderTime,
                  let pTime = self.playerNode.playerTime(forNodeTime: nodeTime) else { return }
            let currentFrame = self.startFrame + AVAudioFramePosition(pTime.sampleTime)
            self.currentTime = min(Double(currentFrame) / self.fileSampleRate, self.duration)
            self.nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.currentTime
            MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlayingInfo
            if self.currentTime >= self.duration {
                self.trackDidFinish()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func trackDidFinish() {
        switch repeatMode {
        case .single:
            seek(to: 0)
            play()
        case .all, .off:
            if let next = adjacentTrack(forward: true) {
                load(track: next, library: libraryProvider?())
                play()
            } else {
                stop()
            }
        }
    }

    // MARK: Loading & transport

    func load(track: Track, library: LibraryStore?) {
        stop()
        currentTrack = track
        guard let library = library else { return }
        let url = library.absoluteURL(for: track)
        do {
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            fileSampleRate = file.processingFormat.sampleRate
            totalFrames = file.length
            duration = Double(totalFrames) / fileSampleRate
            currentTime = 0
            startFrame = 0
            schedule(from: 0)
            state = .loaded

            library.addToRecents(track)
            updateNowPlayingInfo(forceArtworkReload: true, library: library)
        } catch {
            print("AudioFile error: \(error)")
        }
    }

    private func schedule(from frame: AVAudioFramePosition) {
        guard let file = audioFile else { return }
        let framesCount = AVAudioFrameCount(max(0, totalFrames - frame))
        startFrame = frame
        playerNode.stop()
        guard framesCount > 0 else { return }
        playerNode.scheduleSegment(file, startingFrame: frame, frameCount: framesCount, at: nil, completionHandler: nil)
    }

    func play() {
        guard state == .loaded || state == .paused else { return }
        restartEngineIfNeeded()
        if !playerNode.isPlaying { playerNode.play() }
        state = .playing
        updateNowPlayingInfo(library: libraryProvider?())
        beginBackgroundTaskIfNeeded()
    }

    func pause() {
        guard playerNode.isPlaying else { return }
        playerNode.pause()
        state = .paused
        updateNowPlayingInfo(library: libraryProvider?())
        endBackgroundTaskIfPossible()
    }

    func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused, .loaded: play()
        default: break
        }
    }

    func stop() {
        if playerNode.isPlaying { playerNode.stop() }
        currentTime = 0
        state = .idle
        clearNowPlaying()
        endBackgroundTaskIfPossible()
    }

    func seek(to seconds: Double) {
        guard duration > 0 else { return }
        let clamped = max(0, min(seconds, duration))
        let targetFrame = AVAudioFramePosition(clamped * fileSampleRate)
        schedule(from: targetFrame)
        if state == .playing { playerNode.play() }
        currentTime = clamped
        updateNowPlayingInfo(library: libraryProvider?())
    }

    func skipForward(_ seconds: Double = 15) { seek(to: currentTime + seconds) }
    func skipBackward(_ seconds: Double = 15) { seek(to: currentTime - seconds) }

    // MARK: Queue navigation

    private func adjacentTrack(forward: Bool) -> Track? {
        guard let current = currentTrack, let library = libraryProvider?() else { return nil }
        let order = playOrderProvider?() ?? library.tracks
        guard !order.isEmpty else { return nil }

        if shuffleEnabled {
            guard order.count > 1 else { return order.first }
            let candidates = order.filter { $0.id != current.id }
            return candidates.randomElement()
        }
        return forward ? library.track(after: current, in: order)
                       : library.track(before: current, in: order)
    }

    func playNext() {
        guard let next = adjacentTrack(forward: true) else { return }
        load(track: next, library: libraryProvider?())
        play()
    }

    func playPrevious() {
        // Restart current track if more than 3s in, like most real players.
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard let prev = adjacentTrack(forward: false) else { return }
        load(track: prev, library: libraryProvider?())
        play()
    }

    // MARK: Now Playing + Remote Commands

    private func setupRemoteCommands() {
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let r = MPRemoteCommandCenter.shared()
        r.playCommand.isEnabled = true
        r.pauseCommand.isEnabled = true
        r.togglePlayPauseCommand.isEnabled = true
        r.nextTrackCommand.isEnabled = true
        r.previousTrackCommand.isEnabled = true
        r.skipForwardCommand.isEnabled = true
        r.skipForwardCommand.preferredIntervals = [15]
        r.skipBackwardCommand.isEnabled = true
        r.skipBackwardCommand.preferredIntervals = [15]

        r.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
        r.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        r.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause(); return .success
        }
        r.nextTrackCommand.addTarget { [weak self] _ in self?.playNext(); return .success }
        r.previousTrackCommand.addTarget { [weak self] _ in self?.playPrevious(); return .success }
        r.skipForwardCommand.addTarget { [weak self] _ in self?.skipForward(); return .success }
        r.skipBackwardCommand.addTarget { [weak self] _ in self?.skipBackward(); return .success }

        r.changePlaybackPositionCommand.isEnabled = true
        r.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: e.positionTime)
            return .success
        }
    }

    func updateNowPlayingInfo(forceArtworkReload: Bool = false, library: LibraryStore?) {
        guard let track = currentTrack else { return }

        nowPlayingInfo[MPMediaItemPropertyTitle] = track.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = track.displayArtist
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = (state == .playing ? Double(playbackRate) : 0.0)

        if forceArtworkReload { artworkImage = nil }

        if artworkImage == nil {
            if let library = library, let localURL = library.artworkURL(for: track),
               let data = try? Data(contentsOf: localURL), let img = UIImage(data: data) {
                artworkImage = img
            } else if let s = track.artworkURLString, let url = URL(string: s) {
                URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                    guard let self = self, let data = data, let img = UIImage(data: data) else { return }
                    DispatchQueue.main.async {
                        self.artworkImage = img
                        self.applyNowPlayingInfo()
                    }
                }.resume()
            }
        }
        applyNowPlayingInfo()
    }

    private func applyNowPlayingInfo() {
        if let img = artworkImage {
            let artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Interruptions / route changes / lifecycle

    private func observeAudioSession() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleInterruption(_:)), name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
        nc.addObserver(self, selector: #selector(handleRouteChange(_:)), name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance())
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            if state == .playing { playerNode.pause(); state = .paused; updateNowPlayingInfo(library: libraryProvider?()) }
        case .ended:
            let optsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt
            let shouldResume = optsValue.map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
            do { try AVAudioSession.sharedInstance().setActive(true) } catch {}
            restartEngineIfNeeded()
            if shouldResume && state == .paused {
                playerNode.play()
                state = .playing
                updateNowPlayingInfo(library: libraryProvider?())
            }
        @unknown default: break
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            restartEngineIfNeeded(); return
        }
        if reason == .oldDeviceUnavailable, state == .playing {
            // Headphones unplugged etc. — pause, matching system player behaviour.
            playerNode.pause()
            state = .paused
            updateNowPlayingInfo(library: libraryProvider?())
        }
        restartEngineIfNeeded()
    }

    private func observeAppLifecycle() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func appDidEnterBackground() {
        if state == .playing {
            beginBackgroundTaskIfNeeded()
            do { try AVAudioSession.sharedInstance().setActive(true, options: []) } catch {}
            restartEngineIfNeeded()
        }
    }

    @objc private func appWillEnterForeground() {
        endBackgroundTaskIfPossible()
        restartEngineIfNeeded()
    }

    private func beginBackgroundTaskIfNeeded() {
        if bgTask == .invalid {
            bgTask = UIApplication.shared.beginBackgroundTask(withName: "AudioPlayback") { [weak self] in
                self?.endBackgroundTaskIfPossible()
            }
        }
    }

    private func endBackgroundTaskIfPossible() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }
}
