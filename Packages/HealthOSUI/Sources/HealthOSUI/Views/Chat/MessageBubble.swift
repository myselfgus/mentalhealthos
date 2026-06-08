import Foundation
import SwiftUI

public struct MessageBubble: View {
    let message: ChatMessage

    public init(message: ChatMessage) {
        self.message = message
    }
    
    public init(text: String, isCurrentUser: Bool) {
        self.message = ChatMessage(text: text, isCurrentUser: isCurrentUser)
    }
    
    public var body: some View {
        HStack(alignment: .bottom) {
            if message.isCurrentUser {
                Spacer()
            }
            
            VStack(alignment: message.isCurrentUser ? .trailing : .leading, spacing: 8) {
                Text(message.text)
                    .font(.healthBody)
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(message.isCurrentUser ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                metadataRow
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 640, alignment: message.isCurrentUser ? .trailing : .leading)
            .background(bubbleColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            
            if !message.isCurrentUser {
                Spacer()
            }
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 6) {
            statusSymbol
            Text(statusText)
            if let summary = message.metadata.compactSummary {
                Text("·")
                Text(summary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.healthCaption)
        .foregroundStyle(metadataColor)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusSymbol: some View {
        switch message.status {
        case .queued:
            Image(systemName: "clock")
        case .sending:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.72)
        case .sent, .succeeded:
            Image(systemName: "checkmark.circle.fill")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
        }
    }

    private var statusText: String {
        switch message.status {
        case .queued:
            "Na fila"
        case .sending:
            message.isCurrentUser ? "Enviando" : "Processando"
        case .sent:
            "Enviado"
        case .succeeded:
            message.isCurrentUser ? "Enviado" : "Concluído"
        case .failed(let reason):
            reason
        }
    }

    private var bubbleColor: Color {
        switch message.status {
        case .failed:
            return Color.healthDestructive.opacity(message.isCurrentUser ? 0.16 : 0.10)
        default:
            if message.isCurrentUser {
                return Color(nsColor: .selectedContentBackgroundColor)
            }
            return Color(nsColor: .controlBackgroundColor)
        }
    }

    private var borderColor: Color {
        switch message.status {
        case .failed:
            return Color.healthDestructive.opacity(0.55)
        case .sending, .queued:
            return Color.healthPrimary.opacity(0.35)
        default:
            return Color.secondary.opacity(0.16)
        }
    }

    private var textColor: Color {
        if message.isCurrentUser {
            switch message.status {
            case .failed:
                return .primary
            default:
                return Color(nsColor: .selectedMenuItemTextColor)
            }
        }
        return .primary
    }

    private var metadataColor: Color {
        switch message.status {
        case .failed:
            return Color.healthDestructive
        case .sending, .queued:
            return message.isCurrentUser ? Color(nsColor: .selectedMenuItemTextColor).opacity(0.86) : Color.healthPrimary
        default:
            return message.isCurrentUser ? Color(nsColor: .selectedMenuItemTextColor).opacity(0.86) : .secondary
        }
    }
}
