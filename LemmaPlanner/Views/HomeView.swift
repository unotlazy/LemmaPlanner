import SwiftUI

/// The first screen: what needs attention now. Deadlines of saved programs,
/// the next deadlines on the family's list, new programs, and where the
/// saved ones stand.
struct HomeView: View {
    @Environment(AppState.self) private var state
    /// The selected tab, so the tiles and "See all" can switch to My list or Saved.
    @Binding var tab: MainTabs.Tab

    /// How many rows each section shows before "See all".
    private let rows = 5

    var body: some View {
        let comingUp = state.comingUp
        let next = state.nextOnList
        let new = state.newOnList
        let changed = state.savedPrograms.filter { state.dateChanges[$0.key] != nil }
        let dueSoon = comingUp.filter { state.schedule(for: $0).status == .soon }.count

        NavigationStack {
            LemmaList {
                Section {
                    hero(saved: comingUp.first, onList: next.first)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    HStack(spacing: 10) {
                        Tile(count: state.matches.count, label: "On your list", symbol: "list.bullet.rectangle") { tab = .plan }
                        Tile(count: state.savedCount, label: "Saved", symbol: "bookmark.fill") { tab = .saved }
                        Tile(count: dueSoon, label: "Due in 2 weeks", symbol: "clock.fill", alert: dueSoon > 0) { tab = .saved }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } header: {
                    Text(who).textCase(nil).font(.subheadline)
                }

                if let grade = state.gradeQuestion {
                    Section {
                        Button(grade == 13 ? "Yes, in college" : "Yes, grade \(grade)") {
                            state.answerGradeQuestion(movedUp: true)
                        }
                        Button("No, still grade \(state.profile.grade)") {
                            state.answerGradeQuestion(movedUp: false)
                        }
                    } header: {
                        Text("New school year")
                    } footer: {
                        Text(grade == 13
                             ? "Is the student in college now? The list changes with the grade."
                             : "Is the student in grade \(grade) now? The list changes with the grade.")
                    }
                }

                if !changed.isEmpty {
                    Section {
                        ProgramRows(programs: changed)
                    } header: {
                        SectionTitle("Dates changed")
                    }
                }

                Section {
                    if comingUp.isEmpty {
                        Text(state.savedCount == 0
                             ? "Save a program and its deadlines show up here."
                             : "None of your saved programs has a dated deadline ahead.")
                            .foregroundStyle(.secondary)
                    } else {
                        ProgramRows(programs: Array(comingUp.prefix(rows)))
                        if comingUp.count > rows {
                            Button("See all saved programs") { tab = .saved }
                        }
                    }
                } header: {
                    SectionTitle("Your deadlines")
                } footer: {
                    Text("Saved programs you are considering or applying to.")
                }

                if !next.isEmpty {
                    Section {
                        ProgramRows(programs: Array(next.prefix(rows)))
                        Button("See all \(state.matches.count) programs") { tab = .plan }
                    } header: {
                        SectionTitle("Next deadlines on your list")
                    } footer: {
                        Text("Programs that fit your answers and that you have not saved.")
                    }
                }

                if !new.isEmpty {
                    Section {
                        ProgramRows(programs: Array(new.prefix(rows)))
                    } header: {
                        SectionTitle("New on your list")
                    } footer: {
                        Text("Added to the list in the last \(Program.newDays) days.")
                    }
                }

                if state.savedCount > 0 {
                    Section {
                        ForEach(TrackStatus.allCases) { status in
                            let count = state.savedPrograms.filter { state.saved[$0.key] == status }.count
                            if count > 0 {
                                Button { tab = .saved } label: {
                                    LabeledContent {
                                        Text("\(count)")
                                    } label: {
                                        Label(status.label, systemImage: status.symbol)
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    } header: {
                        SectionTitle("Where your programs stand")
                    }
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        HStack(spacing: 14) {
                            Image("FainaPrager")
                                .resizable().scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("About Lemma College Counseling").font(.headline)
                                Text("One-on-one counseling for STEM students")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text(Disclaimer.text)
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { LemmaLogo(height: 34) }
            }
            .navigationDestination(for: Program.self) { ProgramDetailView(opened: $0) }
            .refreshable { await state.refresh() }
        }
    }

    /// The picture at the top, with the one deadline to look at first: the
    /// next one among the saved programs, or else the next one on the list.
    @ViewBuilder private func hero(saved: Program?, onList: Program?) -> some View {
        if let p = saved ?? onList {
            HeroCard(eyebrow: saved != nil ? "Your next deadline" : "Next on your list",
                     title: p.title, detail: deadlineText(p))
                // a link with no arrow, so the whole picture opens the program
                .background(NavigationLink(value: p) { EmptyView() }.opacity(0))
        } else {
            HeroCard(eyebrow: "Lemma Planner", title: "STEM programs that fit, sorted by deadline", detail: nil)
        }
    }

    /// "Application due · Dec 14, 2026 · in 24 days"
    private func deadlineText(_ p: Program) -> String? {
        let schedule = state.schedule(for: p)
        guard let next = schedule.next else { return nil }
        var bits = [next.label.isEmpty ? "Deadline" : next.label, DateText.when(next.when)]
        if next.when.isExactDay, let days = schedule.daysToNext(today: state.today()), days >= 0 {
            bits.append(DateText.relative(days: days))
        }
        return bits.joined(separator: " · ")
    }

    /// "Grade 11, Math, Physics"
    private var who: String {
        var bits = [state.profile.grade == Profile.other ? "Every grade" : GradeLabel.name(state.profile.grade)]
        if !state.profile.subjects.isEmpty {
            bits.append(state.profile.subjects.map(state.subjectLabel).sorted().joined(separator: ", "))
        }
        return bits.joined(separator: ", ")
    }
}

/// The picture at the top of Home, with a line of text over its dark lower half.
private struct HeroCard: View {
    let eyebrow: String
    let title: String
    let detail: String?

    var body: some View {
        Photo(name: "HeroChip", height: 220)
            .overlay {
                LinearGradient(colors: [Brand.navyDeep.opacity(0.05), Brand.navyDeep.opacity(0.55), Brand.navyDeep.opacity(0.95)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(Brand.goldSoft)
                    Text(title)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let detail {
                        Text(detail)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(2)
                    }
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

/// One number with a label under it. Tapping it opens the tab the number comes from.
private struct Tile: View {
    let count: Int
    let label: String
    let symbol: String
    var alert = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .foregroundStyle(alert ? Brand.soon : Brand.goldText)
                Text("\(count)")
                    .font(.system(.title, design: .serif).weight(.semibold))
                    .foregroundStyle(alert ? Brand.soon : Color.primary)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Brand.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) \(label)")
    }
}
