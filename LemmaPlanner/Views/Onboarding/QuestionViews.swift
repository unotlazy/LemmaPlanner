import SwiftUI

// The pickers for each question. The first-run screens and the
// "Your answers" screen in Settings both use them.

struct GradeGrid: View {
    @Environment(AppState.self) private var state
    @Binding var grade: Int
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    /// From grade 6 for a parent and from grade 8 for a student. The grade
    /// already chosen stays, so an older account still shows its own.
    private var grades: [Int] {
        let mine = Profile.grades(student: state.account?.role == "Student")
        return Profile.grades(student: false).filter { mine.contains($0) || $0 == grade }
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(grades, id: \.self) { g in
                ChoiceButton(title: title(g), selected: grade == g) { grade = g }
            }
        }
    }

    private func title(_ g: Int) -> String {
        switch g {
        case Profile.college: return "College"
        case Profile.other: return "Other"
        default: return "\(g)th"
        }
    }
}

struct SubjectGrid: View {
    let subjects: [Subject]
    @Binding var selected: Set<String>
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(subjects) { s in
                ChoiceButton(title: s.label, selected: selected.contains(s.id)) {
                    if selected.contains(s.id) { selected.remove(s.id) } else { selected.insert(s.id) }
                }
            }
        }
    }
}

struct CategoryList: View {
    let categories: [Category]
    @Binding var selected: Set<String>

    var body: some View {
        VStack(spacing: 10) {
            ForEach(categories) { c in
                let on = selected.contains(c.id)
                Button {
                    if on { selected.remove(c.id) } else { selected.insert(c.id) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(on ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.label).font(.headline)
                            if let note = c.note {
                                Text(note).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.tile))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(on ? Color.accentColor : Brand.rule, lineWidth: on ? 1.5 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ChoiceButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 8)
                .foregroundStyle(selected ? Brand.onAccent : Color.primary)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.accentColor : Brand.tile))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? Color.clear : Brand.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
