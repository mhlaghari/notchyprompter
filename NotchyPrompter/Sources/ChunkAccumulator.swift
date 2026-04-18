// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Buffers transcript chunks and fires `onFlush` once the speaker has been
/// silent for `delaySeconds`. Appending a new chunk cancels the pending
/// flush and restarts the timer — standard debounce.
///
/// Used by Pipeline when a mode's `effectiveFireCadence` is `.debounce`.
/// For `.immediate` cadence, Pipeline bypasses the accumulator and fires
/// directly per chunk (after calling `flushNow()` first so any in-flight
/// buffer drains before the immediate call).
@MainActor
final class ChunkAccumulator {
    typealias OnFlush = (String) async -> Void

    private var buffer: String = ""
    private var flushTask: Task<Void, Never>?
    private let onFlush: OnFlush

    init(onFlush: @escaping OnFlush) {
        self.onFlush = onFlush
    }

    var isEmpty: Bool { buffer.isEmpty }

    func append(_ text: String, delaySeconds: Double) {
        if !buffer.isEmpty { buffer += " " }
        buffer += text
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            let ns = UInt64(max(delaySeconds, 0.0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard let self, !Task.isCancelled else { return }
            await self.flushNow()
        }
    }

    func flushNow() async {
        flushTask?.cancel()
        flushTask = nil
        let text = buffer
        buffer = ""
        guard !text.isEmpty else { return }
        await onFlush(text)
    }

    func cancel() {
        flushTask?.cancel()
        flushTask = nil
        buffer = ""
    }
}
