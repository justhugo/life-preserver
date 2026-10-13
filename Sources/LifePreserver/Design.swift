import SwiftUI
import AppKit
#if SWIFT_PACKAGE
import LifePreserverCore
#endif

enum Palette {
    static let background = adaptive(0xF6F5F1, 0x202524)
    static let surface = adaptive(0xFFFFFF, 0x2A302F)
    static let ink = adaptive(0x243B39, 0xEDF1EC)
    static let secondary = adaptive(0x747D76, 0xA5B0A7)
    static let line = adaptive(0xE7E9E2, 0x3E4640)
    static let sea = adaptive(0x386B61, 0x9AC6B1)
    static let blue = adaptive(0x416F89, 0xA2C5E1)
    static let green = adaptive(0x5A8470, 0x95BBA4)
    static let amber = adaptive(0xA2722D, 0xE9BC72)
    static let red = adaptive(0xBC594B, 0xF19D89)
    static let wash = adaptive(0xEBF0E9, 0x323D36)
    static let hero = adaptive(0xEAF0E9, 0x283B34)
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
    static func pressure(_ pressure: Pressure) -> Color {
        switch pressure {
        case .unknown: secondary
        case .comfortable: green
        case .watch: amber
        case .critical, .exhausted: red
        }
    }
}

enum BrandAssets {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }
    static func image(_ name: String, extension suffix: String = "png") -> NSImage? {
        guard let url = bundle.url(forResource: name, withExtension: suffix, subdirectory: "Assets") else { return nil }
        return NSImage(contentsOf: url)
    }
    static var menuBarImage: NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            for (radius, width): (CGFloat, CGFloat) in [(8.1, 0.8), (7.35, 0.6), (3.6, 0.7)] {
                let outline = NSBezierPath(ovalIn: NSRect(x: 9-radius, y: 9-radius, width: radius*2, height: radius*2))
                outline.lineWidth = width; outline.stroke()
            }
            for i in 0..<4 {
                let band = NSBezierPath()
                band.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 5.5,
                    startAngle: CGFloat(i * 90 + 12), endAngle: CGFloat(i * 90 + 56))
                band.lineWidth = 3.7; band.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Life Preserver"
        return image
    }
}

struct Wordmark: View {
    var size: CGFloat = 20
    var body: some View {
        Text("Life Preserver").font(.custom("Baskerville-SemiBold", size: size)).kerning(-0.45)
            .foregroundStyle(Palette.ink).fixedSize()
    }
}

struct PreserverMark: View {
    var monochrome = false
    var body: some View {
        Image(nsImage: monochrome ? BrandAssets.menuBarImage : BrandAssets.image("Preserver") ?? BrandAssets.menuBarImage)
            .resizable().interpolation(.high).aspectRatio(contentMode: .fit).accessibilityHidden(true)
    }
}

struct ProviderMark: View {
    let provider: Provider
    var size: CGFloat = 32
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25).fill(color.opacity(0.08))
            if let mark = BrandAssets.image((provider == .grokBot ? "grok" : provider.rawValue), extension: "svg") {
                Image(nsImage: mark).resizable().renderingMode(.template)
                    .aspectRatio(contentMode: .fit).foregroundStyle(color).padding(size * 0.13)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
    var color: Color {
        switch provider { case .claude: Palette.red; case .openai: Palette.ink; case .grok, .grokBot: Palette.ink }
    }
}

struct Waves: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for row in 0..<5 {
            let y = rect.height * 0.32 + CGFloat(row) * 9
            path.move(to: CGPoint(x: -20, y: y))
            path.addCurve(to: CGPoint(x: rect.width + 20, y: y + 4),
                control1: CGPoint(x: rect.width * 0.32, y: y - 28),
                control2: CGPoint(x: rect.width * 0.55, y: y + 37))
        }
        return path
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Palette.secondary)
            .padding(6)
            .background(configuration.isPressed ? Palette.line : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .foregroundStyle(Color.white)
            .background(Color(red: 0.19, green: 0.36, blue: 0.32).opacity(enabled ? (configuration.isPressed ? 0.82 : 1) : 0.45), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct Tag: View {
    let text: String
    var color: Color = Palette.secondary
    var body: some View {
        Text(text).font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .foregroundStyle(color).background(color.opacity(0.08), in: Capsule())
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(Palette.secondary)
    }
}

struct ErrorNote: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.system(size: 11)).foregroundStyle(Palette.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }
}

extension View {
    func surfaceCard() -> some View {
        self.background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line, lineWidth: 0.7))
    }
}
