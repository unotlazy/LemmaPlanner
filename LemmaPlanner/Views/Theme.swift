import SwiftUI
import UIKit

/// The Lemma look, taken from lemmacollegecounseling.com: navy and gold on a
/// cream page, with serif headings. Dark mode turns it over: a deep navy
/// page with gold as the accent.
enum Brand {
    static let site = URL(string: "https://lemmacollegecounseling.com")!
    static let email = URL(string: "mailto:info@lemmacollegecounseling.com")!
    /// The form a family fills in to start working with Lemma.
    static let application = site.appendingPathComponent("intake.html")

    private static func ui(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// One colour for light mode and one for dark mode.
    private static func pair(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }

    static let navy = Color(uiColor: ui(0x002154))
    static let navyDeep = Color(uiColor: ui(0x031528))
    static let gold = Color(uiColor: ui(0xC59B3E))
    static let goldSoft = Color(uiColor: ui(0xF0CC74))

    /// The page behind lists and forms.
    static let paper = pair(0xF7F4EE, 0x031528)
    /// Rows and cards on the page.
    static let card = pair(0xFFFFFF, 0x0C2440)
    /// One tone for each kind of program, all close to the navy and gold of
    /// the site. Dark mode uses lighter versions so they show on a navy row.
    static func kind(_ category: String) -> Color {
        switch category {
        case "competitions": return pair(0x002154, 0x3A63A8)     // navy
        case "summer-programs": return pair(0xC59B3E, 0xC59B3E)  // gold
        case "research": return pair(0x3F6699, 0x5F8AC2)         // steel blue
        case "internships": return pair(0x5A6B85, 0x7F90AB)      // slate
        case "fellowships": return pair(0x8A6410, 0xB58A2E)      // bronze
        case "scholarships": return pair(0x1F5E63, 0x3B8F95)     // deep teal
        case "events": return pair(0x8E2433, 0xB8475A)           // burgundy
        case "learning": return pair(0xA8925C, 0xBFA873)         // sand
        default: return pair(0x002154, 0x3A63A8)
        }
    }
    /// Buttons and chips that are not selected.
    static let tile = pair(0xF1E9DC, 0x163259)
    /// Thin lines around tiles.
    static let rule = pair(0xE6DFD0, 0x24446F)
    /// Gold that can be read as text: dark gold on cream, light gold on navy.
    static let goldText = pair(0x8A6410, 0xF0CC74)
    /// A deadline in the next 2 weeks.
    static let soon = pair(0x8E2433, 0xFF8FA0)
    /// Text on the accent colour, which is navy in light mode and gold in dark
    /// mode. White on the gold is too faint to read, so dark mode uses navy.
    static let onAccent = pair(0xFFFFFF, 0x002154)

    /// Serif headings in the navigation bars, like the headings on the site.
    static func styleNavigationBars() {
        func serif(_ style: UIFont.TextStyle, bold: Bool) -> UIFont {
            var d = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
            d = d.withDesign(.serif) ?? d
            if bold { d = d.withSymbolicTraits(.traitBold) ?? d }
            return UIFont(descriptor: d, size: 0)
        }
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: serif(.largeTitle, bold: true)]
        bar.titleTextAttributes = [.font: serif(.headline, bold: true)]
    }
}

/// A grouped list on the cream page with white rows.
struct LemmaList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        List {
            Group { content }.listRowBackground(Brand.card)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Brand.paper.ignoresSafeArea())
    }
}

/// The same for a form.
struct LemmaForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Group { content }.listRowBackground(Brand.card)
        }
        .scrollContentBackground(.hidden)
        .background(Brand.paper.ignoresSafeArea())
    }
}

/// A section heading in the serif face.
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(.title3, design: .serif).weight(.semibold))
            .foregroundStyle(Color.primary)
            .textCase(nil)
            .padding(.bottom, 2)
    }
}

/// The Lemma wordmark. The asset has a white and gold version for dark mode.
struct LemmaLogo: View {
    var height: CGFloat = 56

    var body: some View {
        Image("LemmaLogo")
            .resizable().scaledToFit()
            .frame(height: height)
            .accessibilityLabel("Lemma College Counseling")
    }
}

/// A photo that fills a rounded box of a fixed height.
struct Photo: View {
    let name: String
    var height: CGFloat = 190
    var radius: CGFloat = 22

    var body: some View {
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay { Image(name).resizable().scaledToFill() }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The icon and colour for each kind of program.
enum CategoryStyle {
    static func symbol(_ id: String) -> String {
        switch id {
        case "competitions": return "trophy.fill"
        case "summer-programs": return "sun.max.fill"
        case "research": return "flask.fill"
        case "internships": return "briefcase.fill"
        case "fellowships": return "graduationcap.fill"
        case "scholarships": return "dollarsign.circle.fill"
        case "events": return "calendar"
        case "learning": return "book.fill"
        default: return "sparkles"
        }
    }
}

/// The kind of program as a small square in that kind's tone, with its icon in white.
struct CategoryBadge: View {
    let category: String
    var size: CGFloat = 38

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Brand.kind(category))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: CategoryStyle.symbol(category))
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// When the app offers Lemma's counseling. Lemma works with students before
/// college, so a family that picked College is not asked.
enum LemmaOffer {
    /// The kinds of programs a student applies to with essays, records or
    /// recommendations. Competitions, events and free courses are left out.
    static let categories: Set<String> = ["summer-programs", "research", "internships", "fellowships", "scholarships"]

    static func shows(grade: Int) -> Bool { grade != Profile.college }

    static func shows(for program: Program, grade: Int) -> Bool {
        shows(grade: grade) && categories.contains(program.category)
    }
}
