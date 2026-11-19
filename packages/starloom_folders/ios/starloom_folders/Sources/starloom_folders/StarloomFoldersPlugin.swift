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

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "starloom/folders", binaryMessenger: registrar.messenger())
    let instance = StarloomFoldersPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pick":
      pick(result: result)
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
