import Foundation

/// The answers from the first-run questions. Kept on the phone and with the account.
struct Profile: Codable, Equatable {
    enum Format: String, Codable, CaseIterable, Identifiable {
        case any, online, inPerson
        var id: String { rawValue }
        var label: String {
            switch self {
            case .any: return "Online or in person"
            case .online: return "Online only"
            case .inPerson: return "In person only"
            }
        }
    }

    /// 6 to 12, 13 for college, or 0 for "Other", which shows programs for every grade.
    var grade: Int = 10
    /// Subject ids. Empty means every subject.
    var subjects: Set<String> = []
    /// Category ids. Empty means every category.
    var categories: Set<String> = []
    var freeOnly: Bool = false
    var format: Format = .any
    /// Also show programs whose deadlines have passed for this year.
    var showClosed: Bool = false

    static let college = 13
    static let other = 0

    /// The grades to pick from. A parent can pick from grade 6. A student
    /// with their own account starts at grade 8, because most students in
    /// grades 6 and 7 are under 13.
    static func grades(student: Bool) -> [Int] { Array((student ? 8 : 6)...college) + [other] }

    static func isGrade(_ grade: Int) -> Bool { grade == other || (6...college).contains(grade) }
}

extension Profile {
    /// A field that is missing or has a value the app does not know gets its
    /// default. The website also writes these answers, and a newer version of
    /// the app may add fields, so one odd field must not lose the rest.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let g = try? c.decode(Int.self, forKey: .grade), Profile.isGrade(g) { grade = g }
        subjects = (try? c.decode(Set<String>.self, forKey: .subjects)) ?? []
        categories = (try? c.decode(Set<String>.self, forKey: .categories)) ?? []
        freeOnly = (try? c.decode(Bool.self, forKey: .freeOnly)) ?? false
        format = (try? c.decode(String.self, forKey: .format)).flatMap(Format.init(rawValue:)) ?? .any
        showClosed = (try? c.decode(Bool.self, forKey: .showClosed)) ?? false
    }
}

enum Matcher {
    /// Whether a program fits the answers. An empty grades or subjects list
    /// on a program means "any", the same rule the website's filters use.
    static func matches(_ p: Program, _ profile: Profile) -> Bool {
        if profile.grade != Profile.other && !p.grades.isEmpty && !p.grades.contains(profile.grade) { return false }
        if !profile.subjects.isEmpty && !p.subjects.isEmpty
            && profile.subjects.isDisjoint(with: p.subjects) { return false }
        if !profile.categories.isEmpty && !profile.categories.contains(p.category) { return false }
        // a program with no cost listed stays in: the app cannot tell, and the family can check
        if profile.freeOnly && p.costListed && !p.isFree { return false }
        switch profile.format {
        case .any: break
        case .online: if !isOnline(p) { return false }
        case .inPerson: if !isInPerson(p) { return false }
        }
        return true
    }

    // "Hybrid" and an empty format count as both.
    static func isOnline(_ p: Program) -> Bool {
        let f = (p.format ?? "").lowercased()
        return f.isEmpty || f.contains("online") || f.contains("virtual") || f.contains("hybrid") || f.contains("remote")
    }

    static func isInPerson(_ p: Program) -> Bool {
        let f = (p.format ?? "").lowercased()
        return f.isEmpty || f.contains("in person") || f.contains("residential") || f.contains("hybrid")
            || !(f.contains("online") || f.contains("virtual") || f.contains("remote"))
    }

    /// Open programs first, by next deadline. Then programs with no dated
    /// deadline, by name. Closed ones last. `schedule` lets the caller pass
    /// schedules it already worked out.
    static func sorted(_ programs: [Program], today: Date = Date(),
                       schedule: ((Program) -> Schedule)? = nil) -> [Program] {
        let withSchedule = programs.map { ($0, schedule?($0) ?? Schedule($0, today: today)) }
        return withSchedule.sorted { a, b in
            let ra = rank(a.1), rb = rank(b.1)
            if ra != rb { return ra < rb }
            if let na = a.1.next?.when.start, let nb = b.1.next?.when.start, na != nb { return na < nb }
            return a.0.title.localizedCaseInsensitiveCompare(b.0.title) == .orderedAscending
        }
        .map(\.0)
    }

    private static func rank(_ s: Schedule) -> Int {
        switch s.status {
        case .soon, .open: return 0
        case .none: return 1
        case .closed: return 2
        }
    }
}
