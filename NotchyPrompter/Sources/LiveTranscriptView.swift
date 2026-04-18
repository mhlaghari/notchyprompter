// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// A scrollable monospaced view that tails the currently-running session's
/// `.log` file, polling every 500ms and auto-scrolling to the bottom. When
/// no session is active, shows a hint.
struct LiveTranscriptView: View {
    let logURLProvider: () -> URL?
    @State private var text: String = ""
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? "(empty)" : text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .id("bottom")
            }
            .onReceive(timer) { _ in
                reload()
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onAppear { reload() }
        }
    }

    private func reload() {
        guard let url = logURLProvider() else {
            text = "No session running.\n\nStart listening to see the live transcript here."
            return
        }
        if let s = try? String(contentsOf: url, encoding: .utf8) {
            text = s
        }
    }
}
