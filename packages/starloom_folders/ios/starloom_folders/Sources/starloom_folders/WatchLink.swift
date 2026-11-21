import Flutter
import Foundation
import WatchConnectivity

/// iPhone side of the Apple Watch link. Copies songs to the watch with
/// WCSession file transfers (the watch then plays them on its own, no phone
/// needed) and keeps the watch's playlist list up to date.
final class WatchLink: NSObject, WCSessionDelegate {
  static let shared = WatchLink()

  private var channel: FlutterMethodChannel?
  private let outbox: URL = {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("watch-outbox", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }()

  func attach(_ messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "starloom/watch", binaryMessenger: messenger)
    channel = ch
    ch.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard WCSession.isSupported() else {
      result(call.method == "status" ? ["supported": false] : FlutterError(code: "unsupported", message: "No Apple Watch support", details: nil))
      return
    }
    let s = WCSession.default
    switch call.method {
    case "status":
      result([
        "supported": true,
        "activated": s.activationState == .activated,
        "paired": s.isPaired,
        "installed": s.isWatchAppInstalled,
        "reachable": s.isReachable,
        "pending": s.outstandingFileTransfers.count,
      ])
    case "sendFile":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            let meta = args["meta"] as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "path/meta missing", details: nil))
        return
      }
      // Copy first: the original may live in a picked folder the transfer
      // service can't read, and we can delete the copy when it's done.
      let src = URL(fileURLWithPath: path)
      let dst = outbox.appendingPathComponent(UUID().uuidString + "." + src.pathExtension)
      do {
        try FileManager.default.copyItem(at: src, to: dst)
      } catch {
        result(FlutterError(code: "copy", message: error.localizedDescription, details: nil))
        return
      }
      s.transferFile(dst, metadata: WatchLink.plist(meta) as? [String: Any])
      result(true)
    case "context":
      guard let ctx = WatchLink.plist(call.arguments) as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "context missing", details: nil))
        return
      }
      do {
        try s.updateApplicationContext(ctx)
        result(true)
      } catch {
        result(FlutterError(code: "context", message: error.localizedDescription, details: nil))
      }
    case "cancelAll":
      for t in s.outstandingFileTransfers { t.cancel() }
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Flutter's codec types -> property-list types WatchConnectivity accepts.
  static func plist(_ v: Any?) -> Any? {
    switch v {
    case let d as [String: Any]:
      var out: [String: Any] = [:]
      for (k, x) in d { if let y = plist(x) { out[k] = y } }
      return out
    case let a as [Any]:
      return a.compactMap { plist($0) }
    case let t as FlutterStandardTypedData:
      return t.data
    case is NSNull:
      return nil
    case let s as String: return s
    case let n as NSNumber: return n
    case let d as Data: return d
    default: return nil
    }
  }

  private func emit(_ method: String, _ args: [String: Any]) {
    DispatchQueue.main.async { self.channel?.invokeMethod(method, arguments: args) }
  }

  // MARK: WCSessionDelegate

  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    emit("changed", [:])
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    WCSession.default.activate()
  }

  func sessionWatchStateDidChange(_ session: WCSession) { emit("changed", [:]) }
  func sessionReachabilityDidChange(_ session: WCSession) { emit("changed", [:]) }

  func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
    try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    var args: [String: Any] = ["key": fileTransfer.file.metadata?["key"] as? String ?? ""]
    if let e = error { args["error"] = e.localizedDescription }
    emit("transferDone", args)
  }

  /// The watch tells us which songs it has (after deleting some, say).
  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    emit("watchMessage", message)
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    emit("watchMessage", userInfo)
  }
}
