import AVFoundation
import Foundation

final class SilentAudioKeepAlive {
    private var player: AVAudioPlayer?
    private var active = false

    func start() {
        guard !active else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            let url = try Self.writeSilentWAV()
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0.01
            player.prepareToPlay()
            player.play()
            self.player = player
            active = true
        } catch {
            NSLog("[SafeLocation] audio keep-alive failed: %@", error.localizedDescription)
        }
    }

    func stop() {
        player?.stop()
        player = nil
        active = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func writeSilentWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("safe-location-silence.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let sampleRate = 8000
        let samples = sampleRate / 10
        var data = Data()
        func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        let dataSize = UInt32(samples * 2)
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8)); data.append(contentsOf: Array("fmt ".utf8)); u32(16)
        u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(dataSize); data.append(Data(count: Int(dataSize)))
        try data.write(to: url, options: .atomic)
        return url
    }
}
