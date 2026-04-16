import SwiftUI

struct OverlayView: View {
    @ObservedObject var vm: OverlayViewModel

    var body: some View {
        ZStack {
            if !vm.displayText.isEmpty {
                Text(vm.displayText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
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
