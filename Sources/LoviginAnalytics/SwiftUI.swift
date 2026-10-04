#if canImport(SwiftUI)
import SwiftUI

private struct AnalyticsScreenModifier: ViewModifier {
    let screen: String
    let analytics: LoviginAnalytics?
    func body(content: Content) -> some View {
        content.onAppear { Task { await analytics?.trackScreen(screen) } }
    }
}

public extension View {
    /// Each appearance counts once; use on the screen root, not on list cells or nested subviews.
    func loviginScreen(_ name: String, analytics: LoviginAnalytics?) -> some View {
        modifier(AnalyticsScreenModifier(screen: name, analytics: analytics))
    }
}
#endif
