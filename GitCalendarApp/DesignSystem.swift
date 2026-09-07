import SwiftUI

private struct MetricGlassSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.separator.opacity(0.28))
                }
        }
    }
}

extension View {
    func metricGlassSurface() -> some View {
        modifier(MetricGlassSurface())
    }
}
