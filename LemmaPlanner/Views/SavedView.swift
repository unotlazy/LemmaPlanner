import SwiftUI

/// Programs the family saved, grouped by where they are with each one.
struct SavedView: View {
    @Environment(AppState.self) private var state
    /// Kept by MainTabs, so a tapped notification can open a program here.
    @Binding var path: [Program]
    @State private var askAccount = false

    var body: some View {
        let missing = state.missingSaved
        NavigationStack(path: $path) {
            Group {
                if state.saved.isEmpty {
                    ContentUnavailableView(
                        "No saved programs yet",
                        systemImage: "bookmark",
                        description: Text("Open a program in My list and tap \"Save to my programs\". You'll get a reminder before each deadline. Saving needs a free Lemma account."))
                } else {
                    List {
                        if state.account == nil {
                            // the 90-day login ran out
                            Section {
                                Button("Log in") { askAccount = true }
                            } footer: {
                                Text("You are logged out. Log in again to keep these programs with your account and get reminders by email.")
                            }
                        }
                        ForEach(TrackStatus.allCases) { status in
                            let group = state.savedPrograms.filter { state.saved[$0.key] == status }
                            if !group.isEmpty {
                                Section(status.label) {
                                    ForEach(group) { p in
                                        NavigationLink(value: p) { ProgramRow(program: p) }
                                    }
                                }
                            }
                        }
                        if !missing.isEmpty {
                            Section {
                                Button("Remove from saved", role: .destructive) { state.removeMissingSaved() }
                            } header: {
                                Text("No longer on the list")
                            } footer: {
                                Text(missing.count == 1
                                     ? "1 program you saved was taken off the list in an update. It may have ended or moved to a new entry."
                                     : "\(missing.count) programs you saved were taken off the list in an update. They may have ended or moved to new entries.")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Saved")
            .navigationDestination(for: Program.self) { ProgramDetailView(opened: $0) }
            .sheet(isPresented: $askAccount) { AccountGate() }
        }
    }
}
