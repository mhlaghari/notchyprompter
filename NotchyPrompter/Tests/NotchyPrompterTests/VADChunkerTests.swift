// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import NotchyPrompter

/// Tests for `VADChunker`'s grace-period emission model.
///
/// The unit under test is a synchronous frame processor, so we feed it
/// deterministic Float arrays and collect emitted chunks via the internal
/// `process(_:emit:)` seam. No wall-clock timers are involved — all thresholds
/// are measured in cumulative frame-milliseconds.
final class VADChunkerTests: XCTestCase {

    // Build a Float buffer representing `ms` of audio at 16 kHz. `amplitude`
    // controls RMS: a steady ±amp square-wave yields rms = amp.
    private func samples(ms: Int, amplitude: Float, sampleRate: Int = 16_000) -> [Float] {
        let n = sampleRate * ms / 1000
        guard n > 0 else { return [] }
        var buf = [Float](repeating: 0, count: n)
        var sign: Float = 1
        for i in 0..<n {
            buf[i] = sign * amplitude
            // flip every sample — keeps RMS == amplitude
            sign = -sign
        }
        return buf
    }

    // Produce cfg.frameMs-aligned blocks so VADChunker consumes them frame by
    // frame. Simulates the real audio pipeline's arrival cadence.
    private func feed(_ vad: VADChunker,
                      speech: [Float] = [],
                      silence: [Float] = [],
                      out: inout [[Float]]) {
        let emit: ([Float]) -> Void = { out.append($0) }
        if !speech.isEmpty { vad.processForTest(speech, emit: emit) }
        if !silence.isEmpty { vad.processForTest(silence, emit: emit) }
    }

    // Defaults here match the production defaults (see VAD.swift Config).
    private let speechAmp: Float = 0.1      // well above 0.01 threshold
    private let silenceAmp: Float = 0.001   // well below threshold

    // MARK: - Sanity

    func testNoSpeech_NoEmission() {
        let vad = VADChunker()
        var emitted = [[Float]]()
        feed(vad, silence: samples(ms: 5_000, amplitude: silenceAmp), out: &emitted)
        XCTAssertEqual(emitted.count, 0)
    }

    func testShortSpeech_BelowMinSpeech_NoEmission() {
        // 500 ms speech (< 800 ms minSpeechMs) + 2000 ms silence — should not emit.
        let vad = VADChunker()
        var emitted = [[Float]]()
        feed(vad,
             speech: samples(ms: 500, amplitude: speechAmp),
             silence: samples(ms: 2_000, amplitude: silenceAmp),
             out: &emitted)
        XCTAssertEqual(emitted.count, 0,
                       "coughs / throat-clears under minSpeechMs must not produce chunks")
    }

    // MARK: - Core grace-period behaviour

    func testLongSilenceAfterSpeech_Emits() {
        // 1500 ms speech then silence exceeding the grace window → one emission.
        let vad = VADChunker()
        var emitted = [[Float]]()
        feed(vad,
             speech: samples(ms: 1_500, amplitude: speechAmp),
             silence: samples(ms: 1_500, amplitude: silenceAmp),   // > 1200 ms default grace
             out: &emitted)
        XCTAssertEqual(emitted.count, 1)
    }

    func testShortMidParagraphPause_DoesNotEmit() {
        // This is the #8 regression. At old trailingSilenceMs=400 this emitted
        // twice. At PR #10's 900 it *still* flushes (silenceMs hits 900 and
        // fires). At the new grace-period default (1200 ms) a ~1 s breath must
        // not split a paragraph — the rapid-speaker case.
        let vad = VADChunker()
        var emitted = [[Float]]()
        feed(vad,
             speech: samples(ms: 1_500, amplitude: speechAmp),
             silence: samples(ms: 1_050, amplitude: silenceAmp),  // > 900, < 1200
             out: &emitted)
        feed(vad,
             speech: samples(ms: 1_500, amplitude: speechAmp),
             out: &emitted)
        XCTAssertEqual(emitted.count, 0,
                       "~1 s mid-paragraph breath (between PR #10's 900 ms and the new 1200 ms grace) must not emit")
    }

    func testShortMidParagraphPause_ThenLongSilence_EmitsOnce() {
        // Full "rapid-speaker paragraph" scenario: burst, short breath, burst,
        // then the real utterance-end. Expect one coalesced chunk.
        let vad = VADChunker()
        var emitted = [[Float]]()
        feed(vad,
             speech: samples(ms: 1_500, amplitude: speechAmp),
             silence: samples(ms: 700, amplitude: silenceAmp),
             out: &emitted)
        feed(vad,
             speech: samples(ms: 1_500, amplitude: speechAmp),
             silence: samples(ms: 1_500, amplitude: silenceAmp),
             out: &emitted)
        XCTAssertEqual(emitted.count, 1)
        // 1500 + 700 + 1500 + grace (first ~1200 ms of the 1500 ms silence)
        // ≈ 4900 ms ~= 78_400 samples at 16 kHz. Leave slack for frame rounding.
        let frames = emitted[0].count
        XCTAssertGreaterThan(frames, 70_000,
                             "coalesced chunk should span the whole paragraph")
    }

    func testTripleBurstWithTwoShortBreaths_EmitsOnce() {
        // Stress-test the concatenator — three bursts separated by sub-grace
        // silences must yield one chunk.
        let vad = VADChunker()
        var emitted = [[Float]]()
        for _ in 0..<3 {
            feed(vad,
                 speech: samples(ms: 1_500, amplitude: speechAmp),
                 silence: samples(ms: 600, amplitude: silenceAmp),
                 out: &emitted)
        }
        feed(vad, silence: samples(ms: 1_500, amplitude: silenceAmp), out: &emitted)
        XCTAssertEqual(emitted.count, 1)
    }

    // MARK: - Hard cap

    func testHardCap_EmitsEvenWithoutSilence() {
        // 16 s of continuous speech — must flush at the 15 s hard cap even
        // though no grace has elapsed.
        let vad = VADChunker()
        var emitted = [[Float]]()
        feed(vad,
             speech: samples(ms: 16_000, amplitude: speechAmp),
             out: &emitted)
        XCTAssertEqual(emitted.count, 1)
    }
}
