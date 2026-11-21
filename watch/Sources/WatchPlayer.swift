import AVFoundation
import Foundation
import MediaPlayer

/// EQ for the watch: bass, mids, treble and the hi-hat tamer.
struct EQSettings: Codable, Equatable {
  var bass: Double = 0      // 0...12 dB
  var mid: Double = 0       // -6...6 dB
  var treble: Double = 0    // -6...6 dB
  var hats: Bool = false
  var preset: String = "Flat"

  static let presets: [(String, Double, Double, Double)] = [
    ("Flat", 0, 0, 0),
    ("Bass Boost", 6, 0, 0),
    ("Bass Max", 10, -1, -1),
    ("V-Shape", 6, -2, 4),
    ("Vocals", -1, 3, 2),
    ("Treble", 0, 0, 5),
    ("Late Night", 3, 1, -3),
  ]
}

/// Plays songs stored on the watch through AirPods / Bluetooth headphones,
/// with an EQ in between. Works with the phone left at home.
final class WatchPlayer: ObservableObject {
  static let shared = WatchPlayer()

  @Published private(set) var queue: [WSong] = []
  @Published private(set) var index = 0
  @Published private(set) var playing = false
  @Published private(set) var shuffle = false
  @Published var repeatOne = false
  @Published private(set) var sourceName = ""
  @Published var message: String?
  @Published var volume: Double = 0.85 {
    didSet {
      engine.mainMixerNode.outputVolume = Float(volume)
      UserDefaults.standard.set(volume, forKey: "volume")
    }
  }
  @Published var eq = EQSettings() {
    didSet {
      applyEQ()
      if let data = try? JSONEncoder().encode(eq) { UserDefaults.standard.set(data, forKey: "eq") }
    }
  }

  var current: WSong? { queue.indices.contains(index) ? queue[index] : nil }

  private let engine = AVAudioEngine()
  private let node = AVAudioPlayerNode()
  // The watch has no built-in EQ effect, so the EQ runs on the audio as it
  // is read from the file, a chunk at a time, on this queue.
  private let io = DispatchQueue(label: "starloom.watch.audio")
  private let dsp = EQProcessor()
  private var file: AVAudioFile?
  private var inFlight = 0
  private var reachedEnd = false
  private var format: AVAudioFormat?
  private var startFrame: AVAudioFramePosition = 0
  private var generation = 0
  private var sessionReady = false
  private var original: [WSong] = []

  init() {
    if let data = UserDefaults.standard.data(forKey: "eq"), let e = try? JSONDecoder().decode(EQSettings.self, from: data) {
      eq = e
    }
    if UserDefaults.standard.object(forKey: "volume") != nil {
      volume = UserDefaults.standard.double(forKey: "volume")
    }
    engine.attach(node)
    engine.connect(node, to: engine.mainMixerNode, format: nil)
    engine.mainMixerNode.outputVolume = Float(volume)
    setUpRemote()
    NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
      guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
      self?.pause()
    }
    NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
      // AirPods taken out / disconnected: pause like every music app.
      guard let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
      self?.pause()
      self?.sessionReady = false
    }
    NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
      guard let self else { return }
      if self.playing { self.load(self.index, autoplay: true, at: self.position) }
    }
  }

  // MARK: EQ

  func applyPreset(_ p: (String, Double, Double, Double)) {
    eq = EQSettings(bass: p.1, mid: p.2, treble: p.3, hats: eq.hats, preset: p.0)
  }

  /// New EQ takes effect from the next chunk (a fraction of a second).
  private func applyEQ() {
    let s = eq
    let sr = format?.sampleRate ?? 44100
    io.async { self.dsp.configure(s, sampleRate: sr) }
  }

  // MARK: Playback

  /// The watch only plays through Bluetooth headphones; activating the
  /// session shows the "connect AirPods" picker if none are connected.
  private func ensureSession(_ done: @escaping (Bool) -> Void) {
    if sessionReady { done(true); return }
    let s = AVAudioSession.sharedInstance()
    do {
      try s.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
    } catch {
      message = "Audio setup failed"
      done(false)
      return
    }
    s.activate(options: []) { ok, _ in
      DispatchQueue.main.async {
        self.sessionReady = ok
        self.message = ok ? nil : "Connect AirPods or Bluetooth headphones to play"
        done(ok)
      }
    }
  }

  func play(_ songs: [WSong], at i: Int, from name: String, shuffled: Bool = false) {
    guard !songs.isEmpty else { return }
    original = songs
    sourceName = name
    shuffle = shuffled
    if shuffled {
      var rest = songs
      let first = rest.remove(at: min(i, rest.count - 1))
      queue = [first] + rest.shuffled()
      index = 0
    } else {
      queue = songs
      index = min(i, songs.count - 1)
    }
    ensureSession { ok in if ok { self.load(self.index, autoplay: true) } }
  }

  func toggle() { playing ? pause() : resume() }

  func pause() {
    guard playing else { return }
    node.pause()
    playing = false
    updateNowPlaying()
  }

  func resume() {
    guard current != nil else { return }
    ensureSession { ok in
      guard ok else { return }
      if self.file == nil || !self.engine.isRunning {
        self.load(self.index, autoplay: true, at: self.position)
        return
      }
      self.node.play()
      self.playing = true
      self.updateNowPlaying()
    }
  }

  func next() {
    guard !queue.isEmpty else { return }
    load(index + 1 < queue.count ? index + 1 : 0, autoplay: playing || index + 1 < queue.count)
  }

  func previous() {
    guard !queue.isEmpty else { return }
    if position > 3 { seek(to: 0); return }
    load(max(0, index - 1), autoplay: playing)
  }

  func jump(to i: Int) {
    ensureSession { ok in if ok { self.load(i, autoplay: true) } }
  }

  func seek(to seconds: Double) {
    load(index, autoplay: playing, at: max(0, min(seconds, duration - 0.5)))
  }

  func toggleShuffle() {
    guard let cur = current else { shuffle.toggle(); return }
    shuffle.toggle()
    if shuffle {
      var rest = queue
      rest.remove(at: index)
      queue = [cur] + rest.shuffled()
      index = 0
    } else {
      queue = original
      index = original.firstIndex(of: cur) ?? 0
    }
  }

  var duration: Double {
    guard let f = file else { return Double(current?.durationMs ?? 0) / 1000 }
    return Double(f.length) / f.processingFormat.sampleRate
  }

  var position: Double {
    guard let f = file else { return 0 }
    let sr = f.processingFormat.sampleRate
    if let nt = node.lastRenderTime, let pt = node.playerTime(forNodeTime: nt) {
      return min(duration, Double(startFrame + pt.sampleTime) / sr)
    }
    return Double(startFrame) / sr
  }

  private func load(_ i: Int, autoplay: Bool, at seconds: Double = 0) {
    guard queue.indices.contains(i) else { return }
    generation += 1
    let gen = generation
    node.stop()
    index = i
    let song = queue[i]
    do {
      let f = try AVAudioFile(forReading: WatchLibrary.shared.url(of: song))
      file = f
      let fmt = f.processingFormat
      if format == nil || format! != fmt {
        engine.disconnectNodeOutput(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        format = fmt
      }
      startFrame = AVAudioFramePosition(seconds * fmt.sampleRate)
      guard f.length - startFrame > 0 else { finished(); return }
      let s = eq
      io.sync {
        f.framePosition = startFrame
        inFlight = 0
        reachedEnd = false
        dsp.configure(s, sampleRate: fmt.sampleRate)
        dsp.reset()
        // Keep about a second of audio queued ahead.
        for _ in 0..<4 { scheduleNext(f, gen: gen) }
      }
      if !engine.isRunning { try engine.start() }
      if autoplay {
        node.play()
        playing = true
      } else {
        playing = false
      }
      message = nil
    } catch {
      message = "Couldn't play \(song.title)"
      playing = false
    }
    updateNowPlaying()
  }

  /// Reads, EQs and queues the next chunk. Runs on `io`.
  private func scheduleNext(_ f: AVAudioFile, gen: Int) {
    guard gen == generation, !reachedEnd else { return }
    guard let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: 12000) else { return }
    do {
      try f.read(into: buf)
    } catch {
      buf.frameLength = 0
    }
    if buf.frameLength == 0 {
      reachedEnd = true
      if inFlight == 0 { DispatchQueue.main.async { if gen == self.generation { self.finished() } } }
      return
    }
    dsp.process(buf)
    inFlight += 1
    node.scheduleBuffer(buf, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
      guard let self else { return }
      self.io.async {
        guard gen == self.generation else { return }
        self.inFlight -= 1
        if self.reachedEnd {
          if self.inFlight == 0 { DispatchQueue.main.async { if gen == self.generation { self.finished() } } }
        } else {
          self.scheduleNext(f, gen: gen)
        }
      }
    }
  }

  private func finished() {
    if repeatOne { load(index, autoplay: true); return }
    if index + 1 < queue.count {
      load(index + 1, autoplay: true)
    } else {
      playing = false
      load(0, autoplay: false)
    }
  }

  // MARK: Lock screen / AirPods controls

  private func setUpRemote() {
    let c = MPRemoteCommandCenter.shared()
    c.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
    c.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
    c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
    c.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
    c.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
  }

  private func updateNowPlaying() {
    guard let s = current else {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      return
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: s.title,
      MPMediaItemPropertyArtist: s.artist,
      MPMediaItemPropertyAlbumTitle: s.album,
      MPMediaItemPropertyPlaybackDuration: duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
      MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
    ]
  }
}
