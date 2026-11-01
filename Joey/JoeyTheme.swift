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
        // Keep supporting text readable throughout the native interface.
        .custom(weight == .bold ? "HelveticaNeue-Bold" : weight == .medium ? "HelveticaNeue-Medium" : "HelveticaNeue", size:max(14,size))
    }
    static func primary(_ scheme: ColorScheme) -> Color { color(scheme == .dark ? 0x69CD91 : 0x237A48) }
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
        configuration.label.font(JoeyTheme.font(16,weight:.medium))
            .foregroundStyle(enabled ? JoeyTheme.onPrimary(scheme) : Color.secondary)
            .padding(.horizontal,18).padding(.vertical,11)
            .background(enabled ? JoeyTheme.primary(scheme) : Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:4))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(RoundedRectangle(cornerRadius:4))
    }
}

/// Explicit selection colors remain visible even while the window is inactive.
struct JoeyChoiceGroup<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(String, Value)]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Text(title).font(JoeyTheme.font(14,weight:.medium)).foregroundStyle(.secondary)
            HStack(spacing:8) {
                ForEach(options.indices,id:\.self) {index in
                    let option = options[index]
                    let selected = selection == option.1
                    Button {selection = option.1} label: {
                        HStack(spacing:6) {
                            if selected {Image(systemName:"checkmark")}
                            Text(option.0).fixedSize(horizontal:false,vertical:true)
                        }
                        .font(JoeyTheme.font(16,weight:.medium))
                        .frame(maxWidth:.infinity).padding(.horizontal,12).padding(.vertical,10)
                        .foregroundStyle(selected ? JoeyTheme.onPrimary(scheme) : Color.primary)
                        .background(selected ? JoeyTheme.primary(scheme) : Color.primary.opacity(0.05),in:RoundedRectangle(cornerRadius:4))
                        .contentShape(RoundedRectangle(cornerRadius:4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.0)
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .opacity(enabled ? 1 : 0.5)
        .accessibilityElement(children:.contain).accessibilityLabel(title)
    }
}

struct JoeySelectionToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: ToggleStyleConfiguration) -> some View {
        Button {configuration.isOn.toggle()} label: {
            HStack(alignment:.firstTextBaseline,spacing:8) {
                Image(systemName:configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size:20))
                    .foregroundStyle(configuration.isOn ? JoeyTheme.primary(scheme) : .secondary)
                configuration.label
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain).opacity(enabled ? 1 : 0.5)
        .accessibilityRepresentation {
            Toggle(isOn:configuration.$isOn) {configuration.label}.toggleStyle(.checkbox)
        }
    }
}
