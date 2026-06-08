import SwiftUI
import HealthOSCore

public struct MessageBubble: View {
    let text: String
    let isCurrentUser: Bool
    
    public init(text: String, isCurrentUser: Bool) {
        self.text = text
        self.isCurrentUser = isCurrentUser
    }
    
    public var body: some View {
        HStack {
            if isCurrentUser {
                Spacer()
            }
            
            Text(text)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(isCurrentUser ? Color.accentColor : Color.secondary.opacity(0.2))
                .foregroundColor(isCurrentUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            if !isCurrentUser {
                Spacer()
            }
        }
    }
}
