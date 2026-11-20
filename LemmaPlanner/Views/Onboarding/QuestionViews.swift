import SwiftUI

// The pickers for each question. The first-run screens and the
// "Your answers" screen in Settings both use them.

struct GradeGrid: View {
    @Binding var grade: Int
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Profile.grades, id: \.self) { g in
                ChoiceButton(title: g == 13 ? "College" : "\(g)th", selected: grade == g) { grade = g }
            }
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
