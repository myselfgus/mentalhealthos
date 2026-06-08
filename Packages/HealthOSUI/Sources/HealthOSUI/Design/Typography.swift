import SwiftUI

public extension Font {
    static let healthTitle = Font.system(.title, design: .rounded).weight(.bold)
    static let healthHeadline = Font.system(.headline, design: .rounded).weight(.semibold)
    static let healthBody = Font.system(.body, design: .rounded)
    static let healthCallout = Font.system(.callout, design: .rounded)
    static let healthCaption = Font.system(.caption, design: .rounded)
    
    static let healthMono = Font.system(.body, design: .monospaced)
    static let healthNumber = Font.system(.title, design: .rounded).monospacedDigit()
}
