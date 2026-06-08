import SwiftUI

public struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let caption: String?

    public init(title: String, value: String, icon: String, color: Color, caption: String? = nil) {
        self.title = title
        self.value = value
        self.icon = icon
        self.color = color
        self.caption = caption
    }

    public var body: some View {
        HealthOSPanel {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(value)
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(title)
                        .font(.healthCallout)
                        .foregroundColor(.secondary)
                    if let caption {
                        Text(caption)
                            .font(.healthCaption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }
}
