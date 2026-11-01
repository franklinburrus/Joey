#if SWIFT_PACKAGE
import JoeyCore
#endif
import SwiftUI
import AppKit

enum JoeyAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
    func apply() {
        NSApp.appearance = self == .system ? nil : NSAppearance(named:self == .dark ? .darkAqua : .aqua)
    }
}

/// Brand colors belong to the application chrome, never the media renderer.
enum JoeyTheme {
    static func color(_ hex: Int) -> Color {
        Color(.sRGB,red:Double((hex >> 16)&255)/255,green:Double((hex >> 8)&255)/255,blue:Double(hex&255)/255,opacity:1)
    }
    static let verified = color(0x228348)
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(weight == .bold ? "HelveticaNeue-Bold" : weight == .medium ? "HelveticaNeue-Medium" : "HelveticaNeue", size:size)
    }
    static func primary(_ scheme: ColorScheme) -> Color { color(scheme == .dark ? 0xFF6259 : 0xD52B1E) }
    static func background(_ scheme: ColorScheme) -> Color { color(scheme == .dark ? 0x191919 : 0xF7F7F5) }
    static func panel(_ scheme: ColorScheme) -> Color { color(scheme == .dark ? 0x222222 : 0xFCFCFA) }
    static func onPrimary(_ scheme: ColorScheme) -> Color { scheme == .dark ? color(0x191919) : .white }
}

struct JoeyPanel<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment:.leading,spacing:16) {content}
            .frame(maxWidth:.infinity,alignment:.leading).padding(24)
            .background(JoeyTheme.panel(scheme),in:RoundedRectangle(cornerRadius:4))
            .overlay(RoundedRectangle(cornerRadius:4).strokeBorder(Color.primary.opacity(contrast == .increased ? 0.6 : 0.08)))
    }
}

struct JoeyPrimaryButton: ViewModifier {
    func body(content: Content) -> some View { content.buttonStyle(JoeyPrimaryStyle()) }
}

private struct JoeyPrimaryStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label.font(.body.weight(.semibold))
            .foregroundStyle(enabled ? JoeyTheme.onPrimary(scheme) : Color.secondary)
            .padding(.horizontal,18).padding(.vertical,11)
            .background(enabled ? JoeyTheme.primary(scheme) : Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:4))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(RoundedRectangle(cornerRadius:4))
    }
}
