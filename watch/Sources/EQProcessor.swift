import AVFoundation
import Foundation

/// One biquad filter (RBJ "Audio EQ Cookbook"), transposed direct form II,
/// with separate state per channel.
struct Biquad {
  var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
  var z1: [Float] = [0, 0]
  var z2: [Float] = [0, 0]

  enum Kind { case lowShelf, highShelf, peak }

  mutating func set(_ kind: Kind, freq: Double, gainDB: Double, q: Double, sampleRate: Double) {
    if abs(gainDB) < 0.01 {
      b0 = 1; b1 = 0; b2 = 0; a1 = 0; a2 = 0
      return
    }
    let A = pow(10, gainDB / 40)
    let w0 = 2 * Double.pi * min(freq, sampleRate * 0.45) / sampleRate
    let cw = cos(w0), sw = sin(w0)
    var nb0 = 1.0, nb1 = 0.0, nb2 = 0.0, na0 = 1.0, na1 = 0.0, na2 = 0.0
    switch kind {
    case .peak:
      let alpha = sw / (2 * q)
      nb0 = 1 + alpha * A; nb1 = -2 * cw; nb2 = 1 - alpha * A
      na0 = 1 + alpha / A; na1 = -2 * cw; na2 = 1 - alpha / A
    case .lowShelf:
      let alpha = sw / 2 * sqrt((A + 1 / A) * (1 / q - 1) + 2)
      let s = 2 * sqrt(A) * alpha
      nb0 = A * ((A + 1) - (A - 1) * cw + s)
      nb1 = 2 * A * ((A - 1) - (A + 1) * cw)
      nb2 = A * ((A + 1) - (A - 1) * cw - s)
      na0 = (A + 1) + (A - 1) * cw + s
      na1 = -2 * ((A - 1) + (A + 1) * cw)
      na2 = (A + 1) + (A - 1) * cw - s
    case .highShelf:
      let alpha = sw / 2 * sqrt((A + 1 / A) * (1 / q - 1) + 2)
      let s = 2 * sqrt(A) * alpha
      nb0 = A * ((A + 1) + (A - 1) * cw + s)
      nb1 = -2 * A * ((A - 1) + (A + 1) * cw)
      nb2 = A * ((A + 1) + (A - 1) * cw - s)
      na0 = (A + 1) - (A - 1) * cw + s
      na1 = 2 * ((A - 1) - (A + 1) * cw)
      na2 = (A + 1) - (A - 1) * cw - s
    }
    b0 = Float(nb0 / na0); b1 = Float(nb1 / na0); b2 = Float(nb2 / na0)
    a1 = Float(na1 / na0); a2 = Float(na2 / na0)
  }

  var isFlat: Bool { b0 == 1 && b1 == 0 && b2 == 0 && a1 == 0 && a2 == 0 }

  mutating func process(_ x: UnsafeMutablePointer<Float>, count: Int, channel c: Int) {
    if isFlat { return }
    var s1 = z1[c], s2 = z2[c]
    for i in 0..<count {
      let input = x[i]
      let out = b0 * input + s1
      s1 = b1 * input - a1 * out + s2
      s2 = b2 * input - a2 * out
      x[i] = out
    }
    z1[c] = s1; z2[c] = s2
  }

  mutating func reset() {
    z1 = [0, 0]; z2 = [0, 0]
  }
}

/// The watch's EQ chain: bass shelf, mid bump, treble shelf, two hi-hat
/// dips, then a level trim so boosts don't clip.
final class EQProcessor {
  private var filters = [Biquad](repeating: Biquad(), count: 5)
  private var gain: Float = 1
  private var sampleRate: Double = 44100
  private var settings = EQSettings()

  func configure(_ s: EQSettings, sampleRate sr: Double) {
    settings = s
    sampleRate = sr
    filters[0].set(.lowShelf, freq: 100, gainDB: s.bass, q: 0.8, sampleRate: sr)
    filters[1].set(.peak, freq: 1000, gainDB: s.mid, q: 0.7, sampleRate: sr)
    filters[2].set(.highShelf, freq: 6000, gainDB: s.treble, q: 0.8, sampleRate: sr)
    filters[3].set(.peak, freq: 8500, gainDB: s.hats ? -7 : 0, q: 1.4, sampleRate: sr)
    filters[4].set(.peak, freq: 12000, gainDB: s.hats ? -4 : 0, q: 1.4, sampleRate: sr)
    let boost = max(0, s.bass) * 0.6 + max(0, s.mid) * 0.4 + max(0, s.treble) * 0.35
    gain = Float(pow(10, -boost / 20))
  }

  func reset() {
    for i in filters.indices { filters[i].reset() }
  }

  /// Filters the buffer in place.
  func process(_ buffer: AVAudioPCMBuffer) {
    guard let data = buffer.floatChannelData else { return }
    let n = Int(buffer.frameLength)
    let channels = min(2, Int(buffer.format.channelCount))
    for c in 0..<channels {
      let x = data[c]
      for f in filters.indices { filters[f].process(x, count: n, channel: c) }
      if gain != 1 || settings.bass > 0 {
        for i in 0..<n {
          // Trim, then a gentle soft clip for the odd peak that still pokes out.
          let v = x[i] * gain
          x[i] = v > 0.95 || v < -0.95 ? max(-1, min(1, v * 0.98)) : v
        }
      }
    }
  }
}
