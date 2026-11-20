import SwiftUI

/// The first-run questions: grade, subjects, kinds of programs, cost and format.
/// Answers are only saved to the app and the account when the family taps "Show my list".
struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @State private var step = 0
    @State private var draft = Profile()
    @State private var askAccount = false

    private let lastStep = 5

    var body: some View {
        VStack(spacing: 0) {
            if step > 0 {
                ProgressView(value: Double(step), total: Double(lastStep))
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    page
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .background(Brand.paper.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: step)
        // starts from the grade given when the account was made
        .onAppear { draft = state.profile }
        .sheet(isPresented: $askAccount) { AccountGate() }
        // logging in from the first page brings the account's grade
        .onChange(of: state.profile.grade) { _, grade in draft.grade = grade }
    }

    @ViewBuilder private var page: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 16) {
                Photo(name: "HeroChip", height: 200)
                LemmaLogo(height: 52)
                    .padding(.top, 4)
                Text("Find STEM programs that fit, and never miss a deadline")
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                Text("Answer four quick questions. You'll get a list of competitions, summer programs, research, internships, scholarships and more, sorted by the next deadline.")
                    .font(.body).foregroundStyle(.secondary)
                Text("You can see the whole list without an account. Saving programs needs a free Lemma account.")
                    .font(.footnote).foregroundStyle(.secondary)
                if state.account == nil {
                    Button("I already have an account") { askAccount = true }
                        .padding(.top, 4)
                }
            }
        case 1:
            Question("What grade is the student in?", "Use this school year's grade.")
            GradeGrid(grade: $draft.grade)
        case 2:
            Question("Which subjects interest them?", "Pick any. Leave all blank to see every subject.")
            SubjectGrid(subjects: state.subjects, selected: $draft.subjects)
        case 3:
            Question("What kinds of programs?", "Pick any. Leave all blank to see everything.")
            CategoryList(categories: state.categories, selected: $draft.categories)
        case 4:
            Question("Cost and format", "You can change these later in Settings.")
            VStack(spacing: 10) {
                ForEach(Profile.Format.allCases) { f in
                    ChoiceButton(title: f.label, selected: draft.format == f) { draft.format = f }
                }
            }
            Toggle("Only show free programs", isOn: $draft.freeOnly)
                .padding(.top, 8)
        default:
            let count = state.programs.filter { Matcher.matches($0, draft) && state.schedule(for: $0).status != .closed }.count
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: count > 0 ? "checklist" : "magnifyingglass")
                    .font(.system(size: 56)).foregroundStyle(Brand.gold)
                    .padding(.top, 40)
                Text(count > 0 ? "\(count) programs fit" : "Nothing fits yet")
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                Text(count > 0
                     ? "Save the ones you like. The app will remind you 2 weeks and 3 days before each deadline, and on the last day."
                     : "Try more subjects or kinds of programs. Go back to change your answers.")
                    .foregroundStyle(.secondary)
                Text(Disclaimer.text)
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            Spacer()
            Button(nextTitle) {
                if step < lastStep {
                    step += 1
                } else {
                    state.profile = draft
                    state.onboarded = true
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var nextTitle: String {
        switch step {
        case 0: return "Get started"
        case lastStep: return "Show my list"
        default: return "Next"
        }
    }
}

private struct Question: View {
    let title: String
    let hint: String
    init(_ title: String, _ hint: String) { self.title = title; self.hint = hint }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(.title, design: .serif).weight(.semibold))
            Text(hint).foregroundStyle(.secondary)
        }
    }
}
