import Foundation
import WatchConnectivity

struct WSong: Codable, Identifiable, Hashable {
  var key: String
  var title: String
  var artist: String
  var album: String
  var file: String
  var durationMs: Int
  var id: String { key }
}

struct WPlaylist: Codable, Identifiable, Hashable {
  var id: String
  var name: String
  var keys: [String]
}

/// The songs and playlists that live on the watch. The iPhone app copies
/// files over with WatchConnectivity and sends the playlist list as the
/// application context; everything is kept on the watch so it plays with
/// no phone around.
final class WatchLibrary: NSObject, ObservableObject, WCSessionDelegate {
  static let shared = WatchLibrary()

  @Published private(set) var songs: [String: WSong] = [:]
  @Published private(set) var playlists: [WPlaylist] = []
  @Published private(set) var lastReceived: Date?

  let musicDir: URL
  private let indexURL: URL

  private struct Index: Codable {
    var songs: [WSong]
    var playlists: [WPlaylist]
  }

  override init() {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    musicDir = docs.appendingPathComponent("Music", isDirectory: true)
    indexURL = docs.appendingPathComponent("library.json")
    try? FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
    super.init()
    if let data = try? Data(contentsOf: indexURL), let idx = try? JSONDecoder().decode(Index.self, from: data) {
      songs = Dictionary(uniqueKeysWithValues: idx.songs.map { ($0.key, $0) })
      playlists = idx.playlists
    }
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
  }

  // MARK: Queries

  func songs(in pl: WPlaylist) -> [WSong] { pl.keys.compactMap { songs[$0] } }

  var allSongs: [WSong] {
    songs.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
  }

  func url(of s: WSong) -> URL { musicDir.appendingPathComponent(s.file) }

  var bytesUsed: Int64 {
    let files = (try? FileManager.default.contentsOfDirectory(at: musicDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
    return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
  }

  // MARK: Saving

  private func save() {
    let idx = Index(songs: Array(songs.values), playlists: playlists)
    if let data = try? JSONEncoder().encode(idx) { try? data.write(to: indexURL, options: .atomic) }
  }

  /// Safe file name for a song key ("name.mp3|12345").
  private static func fileName(for key: String, ext: String) -> String {
    let base = key.map { $0.isLetter || $0.isNumber ? $0 : "_" }
    return String(base.prefix(120)) + "." + (ext.isEmpty ? "mp3" : ext)
  }

  // MARK: From the iPhone

  private func apply(context: [String: Any]) {
    guard let raw = context["playlists"] as? [[String: Any]] else { return }
    let pls = raw.compactMap { d -> WPlaylist? in
      guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
      return WPlaylist(id: id, name: name, keys: (d["keys"] as? [String]) ?? [])
    }
    DispatchQueue.main.async {
      self.playlists = pls
      // Free space: delete songs no playlist on the watch uses anymore.
      let wanted = Set(pls.flatMap { $0.keys })
      for (key, s) in self.songs where !wanted.contains(key) {
        try? FileManager.default.removeItem(at: self.url(of: s))
        self.songs[key] = nil
      }
      self.save()
      self.reportHave()
    }
  }

  /// Tells the phone what's actually here, so it knows what to (re)send.
  private func reportHave() {
    guard WCSession.default.activationState == .activated else { return }
    WCSession.default.transferUserInfo(["have": Array(songs.keys)])
  }

  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    apply(context: session.receivedApplicationContext)
  }

  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    apply(context: applicationContext)
  }

  /// A song arrived. The file is deleted when this returns, so move it now.
  func session(_ session: WCSession, didReceive file: WCSessionFile) {
    guard let m = file.metadata, let key = m["key"] as? String else { return }
    let ext = (m["ext"] as? String) ?? file.fileURL.pathExtension
    let name = WatchLibrary.fileName(for: key, ext: ext)
    let dst = musicDir.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: dst)
    do {
      try FileManager.default.moveItem(at: file.fileURL, to: dst)
    } catch {
      return
    }
    let song = WSong(
      key: key,
      title: (m["title"] as? String) ?? key,
      artist: (m["artist"] as? String) ?? "",
      album: (m["album"] as? String) ?? "",
      file: name,
      durationMs: (m["durationMs"] as? Int) ?? 0
    )
    DispatchQueue.main.async {
      self.songs[key] = song
      self.lastReceived = Date()
      self.save()
    }
  }
}
