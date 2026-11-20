import SwiftUI
import EventKit
import EventKitUI

struct ProgramDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL
    /// The program as it was when the row was tapped.
    let opened: Program
    /// The same program in the current list, so a new list that arrives while
    /// the page is open shows its new dates. Falls back to the tapped copy if
    /// the new list dropped it.
    private var program: Program { state.program(key: opened.key) ?? opened }
    @State private var calendarStep: Step?
    @State private var askAccount = false
    /// The family tapped Save without an account. Once they are logged in the program is saved.
    @State private var saveAfterLogin = false

    var body: some View {
        let program = self.program
        let sch = state.schedule(for: program)
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(state.categoryLabel(program.category).uppercased())
                            .font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                        if program.isNew() { NewBadge() }
                    }
                    Text(program.title)
                        .font(.system(.title, design: .serif).weight(.semibold))
                    if let org = program.org {
                        Text(org).foregroundStyle(.secondary)
                    }
                    DeadlineLine(schedule: sch, program: program)
                        .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }

            if let change = state.dateChanges[program.key] {
                Section {
                    Label {
                        Text(change + " If you added it to your calendar, change it there too.")
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    }
                } header: {
                    Text("Dates changed")
                }
            }

            Section {
                trackControl
            }

            if let summary = program.summary {
                Section("About") {
                    Text(summary)
                    ForEach(program.body, id: \.self) { Text($0) }
                }
            }

            Section("Details") {
                Detail("Grades", GradeLabel.range(program.grades))
                if !program.subjects.isEmpty {
                    Detail("Subjects", program.subjects.map(state.subjectLabel).joined(separator: ", "))
                }
                if let when = program.when { Detail("When", when) }
                if let cost = program.cost { Detail("Cost", cost) }
                if let format = program.format { Detail("Format", format) }
            }

            if !sch.steps.isEmpty {
                Section {
                    ForEach(sch.steps, id: \.self) { step in
                        TimelineStepRow(step: step) { calendarStep = step }
                    }
                } header: {
                    Text("Timeline")
                } footer: {
                    if sch.steps.contains(where: { $0.when.estimated }) {
                        Text("Dates marked \"About\" are estimates from last year. The program has not announced this year's dates yet.")
                    }
                }
            }

            Section {
                if let link = program.link {
                    Button { openURL(link) } label: {
                        Label("Official page", systemImage: "safari")
                    }
                }
            } footer: {
                Text(Disclaimer.text
                     + (program.checked.map { " Lemma last checked this entry by hand on \($0)." } ?? "")
                     + (program.added.map { " The AI added it to the list on \($0)." } ?? "")
                     + (program.autoChecked.map { " The AI last updated it on \($0)." } ?? ""))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // the note stays while the page is open and goes once the family leaves it
        .onDisappear { state.seenDateChange(program) }
        .sheet(item: $calendarStep) { step in
            AddToCalendarSheet(program: program, step: step)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $askAccount, onDismiss: {
            if state.account == nil { saveAfterLogin = false }
        }) {
            AccountGate()
        }
        .onChange(of: state.account != nil) { _, loggedIn in
            guard loggedIn, saveAfterLogin else { return }
            saveAfterLogin = false
            if state.saved[program.key] == nil { state.toggleSaved(program) }
        }
    }

    /// Saving needs an account, because saved programs are kept with it.
    private func save() {
        if state.account == nil {
            saveAfterLogin = true
            askAccount = true
        } else {
            state.toggleSaved(program)
        }
    }

    @ViewBuilder private var trackControl: some View {
        if let status = state.saved[program.key] {
            Picker(selection: Binding(
                get: { status },
                set: { state.saved[program.key] = $0 })) {
                ForEach(TrackStatus.allCases) { s in
                    Label(s.label, systemImage: s.symbol).tag(s)
                }
            } label: {
                Label("Saved", systemImage: "bookmark.fill").foregroundStyle(Brand.gold)
            }
            Button("Remove from saved", role: .destructive) { state.toggleSaved(program) }
        } else {
            Button { save() } label: {
                Label("Save to my programs", systemImage: "bookmark")
                    .font(.headline)
            }
        }
    }
}

private struct Detail: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }

    var body: some View {
        LabeledContent(label) {
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}

private struct TimelineStepRow: View {
    let step: Step
    let addToCalendar: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.isDeadline ? "flag.fill" : "circle.fill")
                .font(step.isDeadline ? .body : .system(size: 8))
                .frame(width: 20, height: 20)
                .foregroundStyle(step.isPast ? Color.secondary : (step.isDeadline ? Color.red : Brand.gold))
            VStack(alignment: .leading, spacing: 2) {
                Text(step.label.isEmpty ? "Deadline" : step.label)
                    .fontWeight(step.isDeadline ? .semibold : .regular)
                Text(DateText.when(step.when)).font(.subheadline).foregroundStyle(.secondary)
            }
            .foregroundStyle(step.isPast ? .secondary : .primary)
            Spacer()
            if !step.isPast && step.when.isExactDay {
                Button(action: addToCalendar) {
                    Image(systemName: "calendar.badge.plus")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add to calendar")
            }
        }
    }
}

extension Step: Identifiable {
    var id: String { label + DateText.when(when) }
}

/// The system's own "new event" screen, filled in with the deadline.
/// iOS shows it without asking for calendar access.
struct AddToCalendarSheet: UIViewControllerRepresentable {
    let program: Program
    let step: Step
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "\(program.title): \(step.label.isEmpty ? "deadline" : step.label)"
        event.isAllDay = true
        event.startDate = step.when.start
        event.endDate = step.when.range ? step.when.end : step.when.start
        event.url = program.link
        event.notes = "Confirm on the official page: \(program.url ?? "")"
        let vc = EKEventEditViewController()
        vc.eventStore = store
        vc.event = event
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}
