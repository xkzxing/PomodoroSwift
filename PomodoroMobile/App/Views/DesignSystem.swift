import SwiftUI

enum AppPalette {
    static let background = adaptive(0xF2F2F7, 0x131313)
    static let card = adaptive(0xFFFFFF, 0x242424)
    static let ink = adaptive(0x161616, 0xF3F3F3)
    static let secondary = adaptive(0x66666D, 0xB5B5BB)
    static let accent = adaptive(0x1965D2, 0x75B1FF)
    static let soft = adaptive(0xE7E7ED, 0x343439)
    static let line = adaptive(0xDADAE0, 0x3B3B40)
    static let warm = adaptive(0xA98750, 0xD2B27F)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(20)
            .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(AppPalette.line.opacity(0.7), lineWidth: 0.7))
    }
}

extension View {
    func mobileCard() -> some View { modifier(CardModifier()) }
}

struct PrimaryButton: View {
    let title: String
    let symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(AppPalette.background)
                .background(AppPalette.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AppPalette.accent)
                .frame(width: 68, height: 68)
                .background(AppPalette.soft, in: RoundedRectangle(cornerRadius: 22))
                .accessibilityHidden(true)
            Text(title).font(.headline).foregroundStyle(AppPalette.ink)
            Text(message).font(.subheadline).foregroundStyle(AppPalette.secondary)
                .multilineTextAlignment(.center).lineSpacing(5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
    }
}

struct SectionHeading: View {
    let title: String
    var detail: String = ""
    var body: some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(AppPalette.ink)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(AppPalette.secondary)
        }
    }
}

enum MobileDate {
    static func title(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
