import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Taps system-wide output audio via ScreenCaptureKit and yields 16 kHz
/// mono `Float` samples. Requires Screen & System Audio Recording
/// permission (prompted once by TCC on first `SCStream.startCapture()`).
///
/// No virtual audio driver needed — SCK captures what the speakers would
/// play. `excludesCurrentProcessAudio = true` keeps our own output out of
/// the stream.
///
/// We also exclude macOS speech daemons (dictation, Siri TTS, CoreSpeech) via
/// `SCContentFilter.excludingApplications` so recognition chirps and TTS
/// playback don't bleed into the capture. See
/// `docs/superpowers/research-2026-04-19-m13v-feedback.md` for the API
/// reference and bundle-ID list.
final class AudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// macOS processes that play speech-synthesis / dictation audio and
    /// therefore end up in the SCK system mix. Excluding them at the
    /// content-filter level stops the leak described in issue #7.
    private static let speechDaemonBundleIDs: Set<String> = [
        "com.apple.speech.speechsynthesisd",                 // modern TTS daemon
        "com.apple.speech.synthesisserver",                  // legacy TTS
        "com.apple.SpeechRecognitionCore.speechrecognitiond", // dictation
        "com.apple.corespeechd",                             // CoreSpeech framework
        "com.apple.SiriTTSService",                          // Siri TTS
        "com.apple.assistantd",                              // Siri orchestrator
    ]

    private var stream: SCStream?
    private var converter: AVAudioConverter?
    private var outFormat: AVAudioFormat?

    private let continuation: AsyncStream<[Float]>.Continuation
    let samples: AsyncStream<[Float]>

    let targetSampleRate: Double = 16_000

    override init() {
        var cont: AsyncStream<[Float]>.Continuation!
        self.samples = AsyncStream { cont = $0 }
        self.continuation = cont
        super.init()
    }

    func start() async throws {
        // Background daemons don't own on-screen windows, so request the
        // full running-app list — otherwise speechsynthesisd / corespeechd
        // never appear in `content.applications` and the exclusion below is
        // a no-op.
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )
        guard let display = content.displays.first else {
            throw NSError(domain: "AudioCapture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "no display found"])
        }

        let excludedApps = content.applications.filter {
            Self.speechDaemonBundleIDs.contains($0.bundleIdentifier)
        }
        if excludedApps.isEmpty {
            NSLog("AudioCapture: no speech daemons found to exclude (Siri/dictation may be disabled)")
        } else {
            let ids = excludedApps.map(\.bundleIdentifier).joined(separator: ", ")
            NSLog("AudioCapture: excluding %d speech daemons: %@", excludedApps.count, ids)
        }

        // Audio-only filter: attach to a display but request audio capture.
        // SCK applies `excludingApplications` to the audio mix as well as
        // video (WWDC22 session 10155), so this gates speech-daemon output.
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )

        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true
        cfg.excludesCurrentProcessAudio = false  // temporarily relaxed for debugging
        cfg.sampleRate = 48_000
        cfg.channelCount = 2
        // Keep video minimal — we can't turn it off, but we can make it cheap.
        cfg.width = 2
        cfg.height = 2
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps

        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .utility))
        try await s.startCapture()
        self.stream = s

        NSLog("AudioCapture: SCStream started (48 kHz stereo, audio-only)")
    }

    func stop() async {
        guard let s = stream else { return }
        try? await s.stopCapture()
        stream = nil
        continuation.finish()
    }

    // MARK: - SCStreamOutput

    private var audioCbCount: Int = 0
    private var screenCbCount: Int = 0
    private var lastCbLog = Date()

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        if outputType == .audio { audioCbCount += 1 } else { screenCbCount += 1 }
        if Date().timeIntervalSince(lastCbLog) > 3 {
            NSLog("AudioCapture callbacks last 3s: audio=%d screen=%d",
                  audioCbCount, screenCbCount)
            audioCbCount = 0; screenCbCount = 0; lastCbLog = Date()
        }
        guard outputType == .audio, sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }
        guard let floats = Self.convertToMono16k(sampleBuffer,
                                                 targetSR: targetSampleRate,
                                                 converterBox: &self.converter,
                                                 outFormatBox: &self.outFormat) else {
            NSLog("AudioCapture: convertToMono16k returned nil")
            return
        }
        if !floats.isEmpty { continuation.yield(floats) }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("AudioCapture: stream stopped with error: \(error.localizedDescription)")
        continuation.finish()
    }

    // MARK: - CMSampleBuffer → [Float] @ 16 kHz mono

    private static func convertToMono16k(_ sampleBuffer: CMSampleBuffer,
                                         targetSR: Double,
                                         converterBox: inout AVAudioConverter?,
                                         outFormatBox: inout AVAudioFormat?) -> [Float]? {
        guard let fmtDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc)
        else {
            NSLog("AudioCapture: no format description / asbd")
            return nil
        }
        let asbd = asbdPtr.pointee

        // Build an AVAudioFormat that exactly mirrors what SCK delivers.
        // Don't assume interleaving — derive it from the flags.
        var streamDesc = asbd
        guard let inFormat = AVAudioFormat(streamDescription: &streamDesc) else {
            NSLog("AudioCapture: can't build AVAudioFormat from asbd fid=%u flags=0x%x ch=%u sr=%.0f",
                  asbd.mFormatID, asbd.mFormatFlags, asbd.mChannelsPerFrame, asbd.mSampleRate)
            return nil
        }

        // Pull the ABL out of the CMSampleBuffer. SCK can deliver multiple
        // deinterleaved channels, so the ABL must be sized to fit them.
        // Step 1: query the required buffer-list size.
        var sizeNeeded = 0
        var queryStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &sizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard queryStatus == noErr, sizeNeeded > 0 else {
            NSLog("AudioCapture: size query status=%d size=%d", queryStatus, sizeNeeded)
            return nil
        }

        let ablPtr = UnsafeMutableRawPointer.allocate(
            byteCount: sizeNeeded,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { ablPtr.deallocate() }
        let ablTyped = ablPtr.bindMemory(to: AudioBufferList.self, capacity: 1)

        var blockBuffer: CMBlockBuffer?
        queryStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: ablTyped,
            bufferListSize: sizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard queryStatus == noErr else {
            NSLog("AudioCapture: CMSampleBufferGetAudioBufferList status=%d", queryStatus)
            return nil
        }

        guard let pcmIn = AVAudioPCMBuffer(
            pcmFormat: inFormat,
            bufferListNoCopy: ablTyped,
            deallocator: nil
        ) else {
            NSLog("AudioCapture: AVAudioPCMBuffer init failed (numFrames=%d)",
                  sampleBuffer.numSamples)
            return nil
        }

        // Set up the converter once we know the input format.
        if converterBox == nil
            || converterBox?.inputFormat.sampleRate != inFormat.sampleRate
            || converterBox?.inputFormat.channelCount != inFormat.channelCount
            || outFormatBox == nil {
            guard let outFmt = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSR,
                channels: 1,
                interleaved: false
            ) else { return nil }
            outFormatBox = outFmt
            converterBox = AVAudioConverter(from: inFormat, to: outFmt)
            NSLog("AudioCapture: converter %.0f Hz ch=%d -> 16000 Hz mono",
                  inFormat.sampleRate, inFormat.channelCount)
        }
        guard let converter = converterBox, let outFormat = outFormatBox else { return nil }

        let outCapacity = AVAudioFrameCount(
            Double(pcmIn.frameLength) * targetSR / inFormat.sampleRate + 32
        )
        guard let pcmOut = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else {
            return nil
        }

        var err: NSError?
        var delivered = false
        _ = converter.convert(to: pcmOut, error: &err) { _, inputStatus in
            if delivered { inputStatus.pointee = .noDataNow; return nil }
            delivered = true
            inputStatus.pointee = .haveData
            return pcmIn
        }
        if let err {
            NSLog("AudioCapture: convert error: \(err.localizedDescription)")
            return nil
        }

        let frames = Int(pcmOut.frameLength)
        guard let ch0 = pcmOut.floatChannelData?[0], frames > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: ch0, count: frames))
    }
}
