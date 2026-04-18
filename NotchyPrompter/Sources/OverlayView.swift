import SwiftUI

struct OverlayView: View {
    @ObservedObject var vm: OverlayViewModel

    var body: some View {
        ZStack {
            if !vm.displayText.isEmpty {
                Text(vm.displayText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.black.opacity(0.78))
                    )
                    .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.22), value: vm.displayText)
    }
}
