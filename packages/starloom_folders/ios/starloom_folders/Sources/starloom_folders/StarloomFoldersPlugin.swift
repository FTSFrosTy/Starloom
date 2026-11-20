import Flutter
import UIKit
import UniformTypeIdentifiers

/// Lets the user pick a folder in Files (for example On My iPhone > Spotify)
/// and keeps access to it across launches with a bookmark.
/// Apple's guidance: on iOS a regular bookmark of a picked folder persists access.
public class StarloomFoldersPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private var pendingResult: FlutterResult?
  /// URLs we started accessing. Held for the whole app session on purpose.
  private var openURLs: [URL] = []
  /// Google Cast searches in progress (kept alive until they finish).
  private var browsers: [CastBrowser] = []

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "starloom/folders", binaryMessenger: registrar.messenger())
    let instance = StarloomFoldersPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pick":
      pick(result: result)
    case "browseCast":
      let args = call.arguments as? [String: Any]
      let seconds = (args?["seconds"] as? Double) ?? 3.0
      let browser = CastBrowser(seconds: seconds) { [weak self] found in
        self?.browsers.removeAll { $0.done }
        result(found)
      }
      browsers.append(browser)
      browser.start()
    case "restore":
      guard let args = call.arguments as? [String: Any],
            let b64 = args["bookmark"] as? String,
            let data = Data(base64Encoded: b64) else {
        result(FlutterError(code: "bad_args", message: "Missing bookmark", details: nil))
        return
      }
      restore(data: data, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func pick(result: @escaping FlutterResult) {
    if pendingResult != nil {
      result(FlutterError(code: "busy", message: "A picker is already open", details: nil))
      return
    }
    guard let presenter = StarloomFoldersPlugin.topViewController() else {
      result(FlutterError(code: "no_ui", message: "No view controller to present from", details: nil))
      return
    }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    pendingResult = result
    presenter.present(picker, animated: true)
  }

  public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pendingResult else { return }
    pendingResult = nil
    guard let url = urls.first else {
      result(nil)
      return
    }
    let ok = url.startAccessingSecurityScopedResource()
    do {
      let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      if ok { openURLs.append(url) }
      result([
        "path": url.path,
        "name": url.lastPathComponent,
        "bookmark": data.base64EncodedString(),
      ])
    } catch {
      if ok { url.stopAccessingSecurityScopedResource() }
      result(FlutterError(code: "bookmark_failed", message: error.localizedDescription, details: nil))
    }
  }

  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingResult?(nil)
    pendingResult = nil
  }

  private func restore(data: Data, result: @escaping FlutterResult) {
    var stale = false
    do {
      let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
      let ok = url.startAccessingSecurityScopedResource()
      if ok { openURLs.append(url) }
      var out: [String: Any] = ["path": url.path]
      if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
        out["refreshedBookmark"] = fresh.base64EncodedString()
      }
      result(out)
    } catch {
      result(FlutterError(code: "restore_failed", message: error.localizedDescription, details: nil))
    }
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap { $0.windows }
    let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}


/// Finds Google Cast speakers and TVs (Google Home, Nest, Chromecast) on the
/// Wi-Fi with Bonjour. iOS doesn't let apps send raw multicast without a
/// special Apple entitlement, so discovery has to happen here; the actual
/// Cast connection is plain TCP and is done in Dart.
final class CastBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
  private let browser = NetServiceBrowser()
  private var services: [NetService] = []
  private var found: [String: [String: Any]] = [:]
  private let seconds: Double
  private let finish: ([[String: Any]]) -> Void
  private(set) var done = false

  init(seconds: Double, finish: @escaping ([[String: Any]]) -> Void) {
    self.seconds = seconds
    self.finish = finish
  }

  func start() {
    browser.delegate = self
    browser.searchForServices(ofType: "_googlecast._tcp.", inDomain: "local.")
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.stop() }
  }

  private func stop() {
    if done { return }
    done = true
    browser.stop()
    for s in services { s.stop() }
    finish(Array(found.values))
  }

  func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
    services.append(service)
    service.delegate = self
    service.resolve(withTimeout: max(1.0, seconds - 0.5))
  }

  func netServiceDidResolveAddress(_ sender: NetService) {
    guard let host = CastBrowser.ipv4(sender.addresses ?? []) else { return }
    var name = sender.name
    var model = ""
    if let txt = sender.txtRecordData() {
      let dict = NetService.dictionary(fromTXTRecord: txt)
      if let fn = dict["fn"], let s = String(data: fn, encoding: .utf8) { name = s }
      if let md = dict["md"], let s = String(data: md, encoding: .utf8) { model = s }
    }
    found[sender.name] = ["name": name, "host": host, "port": sender.port, "model": model]
  }

  private static func ipv4(_ addresses: [Data]) -> String? {
    for data in addresses {
      var out: String?
      data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        guard let sa = raw.baseAddress?.assumingMemoryBound(to: sockaddr.self), sa.pointee.sa_family == sa_family_t(AF_INET) else { return }
        var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(sa, socklen_t(data.count), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
          out = String(cString: buf)
        }
      }
      if let o = out { return o }
    }
    return nil
  }
}
