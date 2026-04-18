// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Buffers transcript chunks and fires `onFlush` once the speaker has been
/// silent for `delaySeconds`. Appending a new chunk cancels the pending
/// flush and restarts the timer — standard debounce.
///
/// Uses `DispatchQueue.main.asyncAfter` + `DispatchWorkItem` for the timer
/// because Task-based `Task.sleep` + actor isolation was unreliable in
/// practice (timer never fired in one acceptance run). DispatchQueue is
/// well-understood and main-thread-scheduled by construction.
@MainActor
final class ChunkAccumulator {
    typealias OnFlush = (String) async -> Void

    private var buffer: String = ""
    private var pendingWorkItem: DispatchWorkItem?
    private let onFlush: OnFlush

    init(onFlush: @escaping OnFlush) {
        self.onFlush = onFlush
    }

    var isEmpty: Bool { buffer.isEmpty }

    func append(_ text: String, delaySeconds: Double) {
        if !buffer.isEmpty { buffer += " " }
        buffer += text
        DebugLog.write("accumulator: append len=\(text.count) buffer=\(buffer.count) delay=\(delaySeconds)s")
        pendingWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                DebugLog.write("accumulator: timer fired, flushing \(self.buffer.count) chars")
                await self.flushNow()
            }
        }
        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds, execute: work)
    }

    func flushNow() async {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        let text = buffer
        buffer = ""
        guard !text.isEmpty else {
            DebugLog.write("accumulator: flushNow called on empty buffer (noop)")
            return
        }
        DebugLog.write("accumulator: flushing to onFlush len=\(text.count)")
        await onFlush(text)
        DebugLog.write("accumulator: onFlush returned")
    }

    func cancel() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        buffer = ""
    }
}
