import Foundation
import SwiftUI

@MainActor
final class OverlayViewModel: ObservableObject {
    @Published var displayText: String = ""
    @Published var statusLine: String = ""
    @Published var isRunning: Bool = false

    private var hideTask: Task<Void, Never>?

    func setResponse(_ text: String) {
        displayText = text
        scheduleHide(after: 9)
    }

    func appendResponse(_ delta: String) {
        displayText += delta
        scheduleHide(after: 9)
    }

    func setStatus(_ text: String) {
        statusLine = text
        if !text.isEmpty {
            displayText = text
            scheduleHide(after: 2.5)
        }
    }

    func clear() {
        hideTask?.cancel()
        displayText = ""
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            await MainActor.run { self?.displayText = "" }
        }
    }
}
