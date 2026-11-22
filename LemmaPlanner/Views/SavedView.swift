import SwiftUI

/// Programs the family saved, grouped by where they are with each one.
struct SavedView: View {
    @Environment(AppState.self) private var state
    /// Kept by MainTabs, so a tapped notification can open a program here.
    @Binding var path: [Program]

    var body: some View {
        let missing = state.missingSaved
        NavigationStack(path: $path) {
            Group {
                if state.saved.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Photo(name: "Library")
                            Text("No saved programs yet")
                                .font(.system(.title2, design: .serif).weight(.semibold))
                            Text("Open a program in My list and tap \"Save to my programs\". You'll get a reminder before each deadline.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(20)
                    }
                    .background(Brand.paper.ignoresSafeArea())
                } else {
                    LemmaList {
                        ForEach(TrackStatus.allCases) { status in
                            let group = state.savedPrograms.filter { state.saved[$0.key] == status }
                            if !group.isEmpty {
                                Section(status.label) {
                                    ProgramRows(programs: group)
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
                }
            }
            .navigationTitle("Saved")
            .navigationDestination(for: Program.self) { ProgramDetailView(opened: $0) }
        }
    }
}
