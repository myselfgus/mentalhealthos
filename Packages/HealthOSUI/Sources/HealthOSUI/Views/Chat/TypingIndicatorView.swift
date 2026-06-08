import SwiftUI

public struct TypingIndicatorView: View {
    let title: String
    let detail: String?
    @State private var scale: CGFloat = 0.5
    
    public init(title: String = "Processando resposta", detail: String? = nil) {
        self.title = title
        self.detail = detail
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.healthCallout)
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.healthCaption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.healthPrimary)
                            .frame(width: 6, height: 6)
                            .scaleEffect(scale)
                            .opacity(scale)
                            .animation(
                                Animation.easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(0.2 * Double(index)),
                                value: scale
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.healthPrimary.opacity(0.28), lineWidth: 1)
        )
        .onAppear {
            scale = 1.0
        }
        .accessibilityLabel(title)
    }
}
