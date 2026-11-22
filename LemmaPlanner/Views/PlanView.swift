import SwiftUI

/// The family's list: every program that fits their answers, by next deadline.
struct PlanView: View {
    @Environment(AppState.self) private var state
    @State private var search = ""
    @State private var category: String? = nil
    @State private var editing = false

    var body: some View {
        let all = state.matches
        let inCategory = category.map { c in all.filter { $0.category == c } } ?? all
        let searching = !search.trimmingCharacters(in: .whitespaces).isEmpty
        // A search looks through the whole list. Programs that fit the answers
        // come first, and the rest go in their own section below.
        let found = searching ? state.found(search) : []
        let foundKeys = Set(found.map(\.key))
        let fits = Set(all.map(\.key))
        let shown = searching ? inCategory.filter { foundKeys.contains($0.key) } : inCategory
        let others = found.filter { !fits.contains($0.key) }

        NavigationStack {
            LemmaList {
                Section {
                    CategoryChips(programs: all, selected: $category)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text(summary(count: all.count))
                        .textCase(nil)
                        .font(.subheadline)
                } footer: {
                    Text(Disclaimer.text)
                }

                if shown.isEmpty && others.isEmpty {
                    ContentUnavailableView(
                        searching ? "No results" : "Nothing here",
                        systemImage: "magnifyingglass",
                        description: Text(searching ? "Try a different word." : "Try more subjects or kinds of programs in your answers."))
                } else {
                    ProgramRows(programs: shown)
                }

                if !others.isEmpty {
                    Section {
                        ProgramRows(programs: others)
                    } header: {
                        Text("Not on your list")
                    } footer: {
                        Text("These match the search but not your answers, or they are closed for this year.")
                    }
                }
            }
            .navigationTitle("My list")
            .navigationDestination(for: Program.self) { ProgramDetailView(opened: $0) }
            .searchable(text: $search, prompt: "Search programs")
            .refreshable { await state.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = true } label: { Label("Change answers", systemImage: "slider.horizontal.3") }
                }
            }
            .sheet(isPresented: $editing) {
                NavigationStack { AnswersForm(showsDone: true) }
            }
        }
    }

    private func summary(count: Int) -> String {
        var bits = [state.profile.grade == Profile.other ? "every grade" : GradeLabel.name(state.profile.grade)]
        if !state.profile.subjects.isEmpty {
            bits.append(state.profile.subjects.map(state.subjectLabel).sorted().joined(separator: ", "))
        }
        return "\(count) programs for " + bits.joined(separator: ", ")
    }
}

/// A row of buttons to narrow the list to one kind of program.
struct CategoryChips: View {
    @Environment(AppState.self) private var state
    let programs: [Program]
    @Binding var selected: String?

    var body: some View {
        let counts = Dictionary(grouping: programs, by: \.category).mapValues(\.count)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", count: programs.count, on: selected == nil) { selected = nil }
                ForEach(state.categories.filter { counts[$0.id] != nil }) { c in
                    chip(c.label, count: counts[c.id] ?? 0, on: selected == c.id) {
                        selected = selected == c.id ? nil : c.id
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func chip(_ title: String, count: Int, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Text("\(count)").foregroundStyle(on ? Brand.onAccent.opacity(0.8) : Color.secondary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(on ? Brand.onAccent : Color.primary)
            .background(Capsule().fill(on ? Color.accentColor : Brand.card))
            .overlay(Capsule().stroke(on ? Color.clear : Brand.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Rows that open a program's page.
struct ProgramRows: View {
    let programs: [Program]

    var body: some View {
        ForEach(programs, id: \.key) { program in
            NavigationLink(value: program) { ProgramRow(program: program) }
        }
    }
}

struct ProgramRow: View {
    @Environment(AppState.self) private var state
    let program: Program

    var body: some View {
        let sch = state.schedule(for: program)
        HStack(alignment: .top, spacing: 12) {
        CategoryBadge(category: program.category)
            .padding(.top, 2)
        VStack(alignment: .leading, spacing: 4) {
            if program.isNew() { NewBadge() }
            HStack(alignment: .firstTextBaseline) {
                Text(program.title).font(.headline)
                Spacer(minLength: 8)
                if let status = state.saved[program.key] {
                    Image(systemName: status.symbol)
                        .symbolVariant(.fill)
                        .foregroundStyle(Brand.gold)
                        .accessibilityLabel(status.label)
                }
            }
            Text(state.categoryLabel(program.category) + (program.org.map { " · " + $0 } ?? ""))
                .font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(1)
            DeadlineLine(schedule: sch, program: program)
            if state.dateChanges[program.key] != nil {
                Label("Dates changed", systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        }
        .padding(.vertical, 4)
    }
}

/// The NEW label on programs the weekly AI update added in the last 14 days.
struct NewBadge: View {
    var body: some View {
        Text("NEW")
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            // navy on gold: white on gold is too faint
            .foregroundStyle(Brand.navy)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Brand.gold))
            .accessibilityLabel("New")
    }
}

/// "Application due Nov 11, 2026 · in 12 days", or the usual timing in words.
struct DeadlineLine: View {
    let schedule: Schedule
    let program: Program

    var body: some View {
        switch schedule.status {
        case .soon, .open:
            if let next = schedule.next {
                let days = schedule.daysToNext() ?? 0
                let soon = schedule.status == .soon
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Text(DateText.when(next.when)).fontWeight(.semibold)
                        if soon && !next.when.month {
                            Text("· " + DateText.relative(days: days)).fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(soon ? Brand.soon : Color.primary)
                    Text(next.label.isEmpty ? "Deadline" : next.label)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .font(.subheadline)
            }
        case .closed:
            Label("Closed for this year" + (program.when.map { " · usually " + $0.lowercasedFirst } ?? ""), systemImage: "calendar.badge.minus")
                .font(.subheadline).foregroundStyle(.secondary)
        case .none:
            if let when = program.when {
                Label(when, systemImage: "clock")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
