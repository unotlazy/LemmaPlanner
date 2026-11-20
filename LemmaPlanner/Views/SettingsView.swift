import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var confirmReset = false
    @State private var askAccount = false
    @State private var checking = false
    @State private var checkNote: String?

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            Form {
                Section {
                    if let account = state.account {
                        NavigationLink {
                            AccountView()
                        } label: {
                            LabeledContent("Logged in as", value: account.email)
                        }
                    } else {
                        Button("Create an account or log in") { askAccount = true }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    if state.account == nil {
                        Text("A free Lemma account keeps your answers and saved programs, brings them back on a new phone, and gets updates to the list.")
                    }
                }

                Section("Your answers") {
                    NavigationLink {
                        AnswersForm()
                    } label: {
                        LabeledContent("Grade", value: GradeLabel.name(state.profile.grade))
                    }
                }

                Section {
                    Toggle("Deadline reminders", isOn: $state.remindersOn)
                } footer: {
                    Text("For saved programs you are considering or applying to: a notification 2 weeks and 3 days before the deadline, and on the last day, at 9 am. Only for deadlines with an exact date. Also a notification when an update to the list changes their dates.")
                }

                Section {
                    if let feed = state.feed {
                        LabeledContent("Programs", value: "\(feed.programs.count)")
                        LabeledContent("List updated", value: Self.day(feed.generated))
                    }
                    Button {
                        Task { await check() }
                    } label: {
                        HStack {
                            Text("Check for updates")
                            if checking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(checking)
                    if let checkNote {
                        Text(checkNote).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Program list")
                } footer: {
                    Text("The list comes from the Resources pages on the Lemma College Counseling site and updates on its own when the app opens or you come back to it. " + Disclaimer.text)
                }

                Section {
                    Link(destination: Brand.site) {
                        Label("Lemma College Counseling", systemImage: "graduationcap")
                    }
                } footer: {
                    Text("Want help choosing programs or planning applications? Lemma offers one-on-one counseling for STEM students.")
                }

                Section {
                    Button("Start over", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Clears your answers and saved programs, here and on your account if you are logged in, and asks the questions again. The grade stays.")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $askAccount) { AccountGate() }
            .confirmationDialog("Clear your answers and saved programs?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Start over", role: .destructive) { state.resetAll() }
            }
        }
    }

    private func check() async {
        checking = true
        checkNote = nil
        switch await state.refresh() {
        case .updated: checkNote = "The list is updated."
        case .upToDate: checkNote = "You already have the latest list."
        case .failed:
            // the site only gives the list to a logged-in account
            checkNote = state.account == nil
                ? "Log in to get updates to the list. Until then the app uses the list it came with."
                : "Could not get the list. Check the connection and try again."
        }
        checking = false
    }

    static func day(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) else { return String(iso.prefix(10)) }
        return d.formatted(date: .abbreviated, time: .omitted)
    }
}

/// The first-run questions again, as one screen. Changes apply right away.
struct AnswersForm: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    /// True when shown as a sheet from My list, which needs its own Done button.
    var showsDone = false

    var body: some View {
        @Bindable var state = state
        Form {
            Section("Grade") {
                GradeGrid(grade: $state.profile.grade)
                    .padding(.vertical, 4)
            }
            Section {
                SubjectGrid(subjects: state.subjects, selected: $state.profile.subjects)
                    .padding(.vertical, 4)
            } header: {
                Text("Subjects")
            } footer: {
                Text("None picked means every subject.")
            }
            Section {
                CategoryList(categories: state.categories, selected: $state.profile.categories)
                    .padding(.vertical, 4)
            } header: {
                Text("Kinds of programs")
            } footer: {
                Text("None picked means everything.")
            }
            Section("Cost and format") {
                Picker("Format", selection: $state.profile.format) {
                    ForEach(Profile.Format.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Only free programs", isOn: $state.profile.freeOnly)
                Toggle("Show programs closed for this year", isOn: $state.profile.showClosed)
            }
        }
        .navigationTitle("Your answers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
