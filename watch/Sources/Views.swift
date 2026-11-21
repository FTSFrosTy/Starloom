import SwiftUI

// MARK: - Look (same palette as the phone app's Moonlit theme)

enum Clay {
  static let night = Color(red: 0.07, green: 0.055, blue: 0.11)
  static let plum = Color(red: 0.23, green: 0.14, blue: 0.28)
  static let bruise = Color(red: 0.16, green: 0.11, blue: 0.2)
  static let candle = Color(red: 0.95, green: 0.65, blue: 0.25)
  static let pumpkin = Color(red: 0.88, green: 0.44, blue: 0.23)
  static let bone = Color(red: 0.93, green: 0.89, blue: 0.82)
  static let ash = Color(red: 0.61, green: 0.56, blue: 0.64)
  static let rose = Color(red: 0.83, green: 0.36, blue: 0.47)
  static let moss = Color(red: 0.5, green: 0.64, blue: 0.42)

  static func title(_ size: CGFloat) -> Font { .custom("MysteryQuest", size: size) }

  static var background: some View {
    LinearGradient(colors: [plum, night], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
  }
}

/// Stop-motion "boil": tiny wobble that changes 8 times a second.
struct Boil: ViewModifier {
  var on: Bool
  var seed: Int
  var amount: CGFloat = 1

  func body(content: Content) -> some View {
    if on {
      TimelineView(.periodic(from: .now, by: 1.0 / 8)) { t in
        let f = Int(t.date.timeIntervalSinceReferenceDate * 8)
        content
          .rotationEffect(.degrees(Boil.noise(seed, f, 1) * 1.6 * amount))
          .offset(x: Boil.noise(seed, f, 2) * 0.8 * amount, y: Boil.noise(seed, f, 3) * 0.8 * amount)
      }
    } else {
      content
    }
  }

  static func noise(_ a: Int, _ b: Int, _ c: Int) -> CGFloat {
    var h = (a &* 374761393 &+ b &* 668265263 &+ c &* 1442695041) & 0x7fffffff
    h = ((h ^ (h >> 13)) &* 1274126177) & 0x7fffffff
    h = h ^ (h >> 16)
    return CGFloat(h & 0xffff) / 0xffff * 2 - 1
  }
}

/// A squishy clay button: lumpy blob with a soft highlight and shadow.
struct ClayButtonStyle: ButtonStyle {
  var color: Color = Clay.pumpkin
  var size: CGFloat = 44

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(Clay.bone)
      .frame(width: size, height: size)
      .background(
        Circle()
          .fill(RadialGradient(colors: [color.opacity(1), color.opacity(0.75)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.7))
          .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 1.5))
          .overlay(
            Ellipse().fill(Color.white.opacity(0.22)).frame(width: size * 0.38, height: size * 0.2).offset(x: -size * 0.14, y: -size * 0.22)
          )
          .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
      )
      .scaleEffect(x: configuration.isPressed ? 1.12 : 1, y: configuration.isPressed ? 0.86 : 1)
      .animation(.spring(response: 0.25, dampingFraction: 0.45), value: configuration.isPressed)
  }
}

// MARK: - Root

struct RootView: View {
  var body: some View {
    TabView {
      NowPlayingView()
      LibraryView()
      EQView()
    }
    .tabViewStyle(.verticalPage)
  }
}

// MARK: - Now playing

struct NowPlayingView: View {
  @EnvironmentObject var player: WatchPlayer
  @EnvironmentObject var library: WatchLibrary
  @State private var crown: Double = 0.85

  var body: some View {
    ZStack {
      Clay.background
      if let song = player.current {
        VStack(spacing: 6) {
          Text(player.sourceName.isEmpty ? "Starloom" : player.sourceName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Clay.ash)
            .lineLimit(1)
          Text(song.title)
            .font(Clay.title(20))
            .foregroundStyle(Clay.bone)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .modifier(Boil(on: player.playing, seed: song.title.count, amount: 0.6))
          Text(song.artist)
            .font(.system(size: 13))
            .foregroundStyle(Clay.ash)
            .lineLimit(1)
          ProgressBar()
          HStack(spacing: 10) {
            Button { player.previous() } label: { Image(systemName: "backward.fill") }
              .buttonStyle(ClayButtonStyle(color: Clay.bruise, size: 38))
            Button { player.toggle() } label: {
              Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.system(size: 22, weight: .bold))
            }
            .buttonStyle(ClayButtonStyle(color: Clay.pumpkin, size: 54))
            .overlay(VolumeRing(level: player.volume).allowsHitTesting(false))
            .modifier(Boil(on: player.playing, seed: 53))
            Button { player.next() } label: { Image(systemName: "forward.fill") }
              .buttonStyle(ClayButtonStyle(color: Clay.bruise, size: 38))
          }
          HStack(spacing: 22) {
            Button { player.toggleShuffle() } label: {
              Image(systemName: "shuffle").foregroundStyle(player.shuffle ? Clay.candle : Clay.ash)
            }
            Button { player.repeatOne.toggle() } label: {
              Image(systemName: "repeat.1").foregroundStyle(player.repeatOne ? Clay.candle : Clay.ash)
            }
          }
          .buttonStyle(.plain)
          .font(.system(size: 15))
          if let m = player.message {
            Text(m).font(.system(size: 11)).foregroundStyle(Clay.rose).multilineTextAlignment(.center)
          }
        }
        .padding(.horizontal, 6)
      } else {
        VStack(spacing: 8) {
          Image(systemName: "moon.stars.fill").font(.system(size: 30)).foregroundStyle(Clay.candle)
            .modifier(Boil(on: true, seed: 7))
          Text("Starloom").font(Clay.title(24)).foregroundStyle(Clay.bone)
          Text(library.songs.isEmpty
               ? "Put playlists on your watch from Starloom on your iPhone: Settings › Apple Watch."
               : "Swipe up for your playlists.")
            .font(.system(size: 12))
            .foregroundStyle(Clay.ash)
            .multilineTextAlignment(.center)
        }
        .padding()
      }
    }
    // Digital Crown = volume.
    .focusable(true)
    .digitalCrownRotation($crown, from: 0, through: 1, by: 0.02, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
    .onAppear { crown = player.volume }
    .onChange(of: crown) { _, v in player.volume = v }
  }
}

/// Thin ring around the play button showing the volume.
struct VolumeRing: View {
  var level: Double

  var body: some View {
    Circle()
      .trim(from: 0, to: level)
      .stroke(Clay.candle.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
      .rotationEffect(.degrees(-90))
      .frame(width: 62, height: 62)
  }
}

struct ProgressBar: View {
  @EnvironmentObject var player: WatchPlayer

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
      let d = max(1, player.duration)
      let p = min(1, player.position / d)
      VStack(spacing: 2) {
        GeometryReader { g in
          ZStack(alignment: .leading) {
            Capsule().fill(Clay.bruise)
            Capsule().fill(Clay.candle).frame(width: max(4, g.size.width * p))
          }
        }
        .frame(height: 4)
        HStack {
          Text(Self.fmt(player.position))
          Spacer()
          Text(Self.fmt(d))
        }
        .font(.system(size: 10).monospacedDigit())
        .foregroundStyle(Clay.ash)
      }
    }
    .padding(.horizontal, 8)
  }

  static func fmt(_ s: Double) -> String {
    let t = Int(max(0, s))
    return String(format: "%d:%02d", t / 60, t % 60)
  }
}

// MARK: - Library

struct LibraryView: View {
  @EnvironmentObject var library: WatchLibrary

  var body: some View {
    NavigationStack {
      List {
        if library.playlists.isEmpty {
          Text("No playlists yet. On your iPhone: Starloom › Settings › Apple Watch.")
            .font(.system(size: 13))
            .foregroundStyle(Clay.ash)
        }
        ForEach(library.playlists) { pl in
          let songs = library.songs(in: pl)
          NavigationLink {
            SongListView(title: pl.name, songs: songs)
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(pl.name).font(Clay.title(17)).foregroundStyle(Clay.bone).lineLimit(1)
              Text(songs.count == pl.keys.count ? "\(songs.count) songs" : "\(songs.count) of \(pl.keys.count) copied")
                .font(.system(size: 11)).foregroundStyle(Clay.ash)
            }
          }
          .listRowBackground(RoundedRectangle(cornerRadius: 14).fill(Clay.bruise))
        }
        if !library.songs.isEmpty {
          NavigationLink {
            SongListView(title: "All Songs", songs: library.allSongs)
          } label: {
            Label("All Songs", systemImage: "music.note.list").foregroundStyle(Clay.bone)
          }
          .listRowBackground(RoundedRectangle(cornerRadius: 14).fill(Clay.plum))
          Text("\(library.songs.count) songs · \(ByteCountFormatter.string(fromByteCount: library.bytesUsed, countStyle: .file))")
            .font(.system(size: 11))
            .foregroundStyle(Clay.ash)
            .listRowBackground(Color.clear)
        }
      }
      .navigationTitle("Library")
      .containerBackground(Clay.plum.gradient, for: .navigation)
    }
  }
}

struct SongListView: View {
  let title: String
  let songs: [WSong]
  @EnvironmentObject var player: WatchPlayer

  var body: some View {
    List {
      HStack(spacing: 8) {
        Button { player.play(songs, at: 0, from: title) } label: { Image(systemName: "play.fill") }
          .buttonStyle(ClayButtonStyle(color: Clay.pumpkin, size: 40))
        Button { player.play(songs, at: Int.random(in: 0..<max(1, songs.count)), from: title, shuffled: true) } label: {
          Image(systemName: "shuffle")
        }
        .buttonStyle(ClayButtonStyle(color: Clay.plum, size: 40))
      }
      .frame(maxWidth: .infinity)
      .listRowBackground(Color.clear)
      .disabled(songs.isEmpty)
      ForEach(Array(songs.enumerated()), id: \.element.key) { i, s in
        Button {
          player.play(songs, at: i, from: title)
        } label: {
          VStack(alignment: .leading, spacing: 1) {
            Text(s.title)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(player.current?.key == s.key ? Clay.candle : Clay.bone)
              .lineLimit(1)
            Text(s.artist).font(.system(size: 11)).foregroundStyle(Clay.ash).lineLimit(1)
          }
        }
        .listRowBackground(RoundedRectangle(cornerRadius: 12).fill(Clay.bruise))
      }
    }
    .navigationTitle(title)
  }
}

// MARK: - EQ

struct EQView: View {
  @EnvironmentObject var player: WatchPlayer

  var body: some View {
    NavigationStack {
      List {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(EQSettings.presets, id: \.0) { p in
              Button(p.0) { player.applyPreset(p) }
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(player.eq.preset == p.0 ? Clay.candle : Clay.bruise))
                .foregroundStyle(player.eq.preset == p.0 ? Clay.night : Clay.bone)
                .buttonStyle(.plain)
            }
          }
        }
        .listRowBackground(Color.clear)

        knob("Bass", value: Binding(get: { player.eq.bass }, set: { player.eq.bass = $0; player.eq.preset = "Custom" }),
             range: 0...12, color: Clay.pumpkin)
        knob("Mids", value: Binding(get: { player.eq.mid }, set: { player.eq.mid = $0; player.eq.preset = "Custom" }),
             range: -6...6, color: Clay.moss)
        knob("Treble", value: Binding(get: { player.eq.treble }, set: { player.eq.treble = $0; player.eq.preset = "Custom" }),
             range: -6...6, color: Clay.ash)

        Toggle(isOn: Binding(get: { player.eq.hats }, set: { player.eq.hats = $0 })) {
          VStack(alignment: .leading) {
            Text("Hi-hat tamer").foregroundStyle(Clay.bone)
            Text("Softens harsh hi-hats").font(.system(size: 10)).foregroundStyle(Clay.ash)
          }
        }
        .tint(Clay.candle)
        .listRowBackground(RoundedRectangle(cornerRadius: 12).fill(Clay.bruise))
      }
      .navigationTitle("EQ")
      .containerBackground(Clay.pumpkin.opacity(0.35).gradient, for: .navigation)
    }
  }

  private func knob(_ name: String, value: Binding<Double>, range: ClosedRange<Double>, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(name).foregroundStyle(Clay.bone)
        Spacer()
        Text(value.wrappedValue == 0 ? "0 dB" : String(format: "%+.0f dB", value.wrappedValue))
          .font(.system(size: 12).monospacedDigit())
          .foregroundStyle(color)
      }
      Slider(value: value, in: range, step: 1)
        .tint(color)
    }
    .listRowBackground(RoundedRectangle(cornerRadius: 12).fill(Clay.bruise))
  }
}
