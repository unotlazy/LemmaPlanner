import SwiftUI

/// About the app and about Lemma College Counseling. The text follows the
/// About page on the site.
struct AboutView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 10) {
                    LemmaLogo(height: 72)
                    Text("College counseling for STEM students")
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                Photo(name: "Campus")

                Card("About this app") {
                    Text("Lemma Planner is a free app from Lemma College Counseling. It shows STEM competitions, summer programs, research, internships, fellowships and scholarships that fit a student's grade and interests, sorted by the next deadline.")
                    Text("Save a program and the app reminds you 2 weeks before each deadline, 3 days before, and on the last day.")
                    Text(Disclaimer.text)
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Card("The counselor") {
                    HStack(spacing: 14) {
                        Image("FainaPrager")
                            .resizable().scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Brand.gold, lineWidth: 2))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Faina Prager")
                                .font(.system(.title3, design: .serif).weight(.semibold))
                            Text("Massachusetts").foregroundStyle(.secondary)
                        }
                    }
                    Text("Faina worked as a software engineer for many years. She then taught AP Computer Science A and mentored students in advanced STEM courses. She also served on the admissions team at Santa Clara University, where she read applications from the university's side.")
                    Text("She works only with students headed for mathematics, science, engineering, computer science and medicine. STEM applicants are judged on the order of their advanced courses, on research and competitions, and on technical work that a reader in the field can follow.")
                    Text("For essays she works with a writing advisor. The student writes every word.")
                }

                Photo(name: "Library", height: 170)

                Card("Working with Lemma") {
                    Text("Lemma takes a small number of families each year. It starts with an application. If it looks like a fit, there is a free 45-minute interview, and a quote after it.")
                    Text("Students in a counseling program can also get tutoring in mathematics, physics and computer science, and test preparation.")
                    Button {
                        openURL(Brand.site.appendingPathComponent("intake.html"))
                    } label: {
                        Text("Start the application").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .foregroundStyle(Brand.onAccent)
                    HStack {
                        Link("Website", destination: Brand.site)
                        Spacer()
                        Link("Email Lemma", destination: Brand.email)
                    }
                    .font(.body.weight(.medium))
                }

                HStack {
                    Link("Terms of Use", destination: LemmaAPI.terms)
                    Spacer()
                    Link("Privacy Policy", destination: LemmaAPI.privacy)
                }
                .font(.subheadline)
                .padding(.horizontal, 4)

                Text("Lemma Planner \(version)\nMade by Prager Technologies")
                    .multilineTextAlignment(.center)
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .background(Brand.paper.ignoresSafeArea())
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}

/// A white box with a serif heading.
private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(.title2, design: .serif).weight(.semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Brand.card))
    }
}
