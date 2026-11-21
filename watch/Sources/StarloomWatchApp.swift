import SwiftUI

@main
struct StarloomWatchApp: App {
  @StateObject private var library = WatchLibrary.shared
  @StateObject private var player = WatchPlayer.shared

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(library)
        .environmentObject(player)
    }
  }
}
