import Foundation

/// The file the app reads: programs.json, built from the Lemma site's data/
/// folder by scripts/build-programs-json.js in the LemmaCollegeCounseling repo.
struct ProgramFeed: Codable {
    var version: Int
    var generated: String
    var subjects: [Subject]
    var categories: [Category]
    var programs: [Program]
}

extension ProgramFeed {
    /// Reads the programs one at a time and skips any the app cannot read,
    /// so one bad entry from the weekly AI update does not lose the whole list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        generated = try c.decode(String.self, forKey: .generated)
        subjects = try c.decode([Subject].self, forKey: .subjects)
        categories = try c.decode([Category].self, forKey: .categories)
        programs = try c.decode([Skippable<Program>].self, forKey: .programs).compactMap(\.value)
    }
}

/// Decodes to nil when the value cannot be read.
private struct Skippable<T: Decodable>: Decodable {
    var value: T?
    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(T.self)
    }
}

struct Subject: Codable, Hashable, Identifiable {
    var id: String
    var label: String
}

struct Category: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var note: String?
}

/// One entry from a Resources page: a competition, summer program, scholarship and so on.
struct Program: Codable, Hashable, Identifiable {
    var category: String
    var id: String
    var title: String
    var org: String?
    var summary: String?
    var body: [String]
    var url: String?
    /// 1 to 12 are school grades, 13 is college, 14 is graduate school.
    /// Empty means any grade.
    var grades: [Int]
    /// Subject ids. Empty means open to any subject.
    var subjects: [String]
    var when: String?
    var timeline: [TimelineRow]
    var cost: String?
    var format: String?
    /// The day someone at Lemma last confirmed the entry by hand.
    var checked: String?
    /// The day the site's weekly AI update last looked at the entry.
    var autoChecked: String?
    /// The day the weekly AI update added the entry, for programs it found.
    var added: String?

    /// Ids are only unique within one Resources page, so the app uses both.
    var key: String { category + "/" + id }

    /// True when the program costs the family nothing. "Paid" and "Paid
    /// stipend" mean the student gets money, and "Unpaid" is an internship
    /// with no pay and no fee.
    var isFree: Bool {
        let c = (cost ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return ["free", "usually free", "paid", "unpaid"].contains { c.hasPrefix($0) }
    }

    /// False when the entry does not say what the program costs.
    var costListed: Bool {
        !(cost ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    var link: URL? { url.flatMap(URL.init(string:)) }

    /// How long a program the AI found is marked NEW. Same as resources.js on the website.
    static let newDays = 14

    /// True for 14 days after the weekly AI update added the program.
    func isNew(today: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let raw = added, let when = WhenDate.parse(raw, calendar: calendar), !when.month,
              let days = calendar.dateComponents([.day], from: when.start, to: calendar.startOfDay(for: today)).day
        else { return false }
        return days >= 0 && days <= Program.newDays
    }
}

/// Shown wherever the list is. The site updates the list with AI every week
/// and nobody checks those updates by hand, so the dates can be wrong.
enum Disclaimer {
    static let text = "Dates, costs and rules can be wrong. Always confirm them on the program's official page before you apply."
}

/// A line of a timeline: ["2026-11-11", "Application due", "deadline"].
struct TimelineRow: Codable, Hashable {
    var date: String
    var label: String
    var isDeadline: Bool

    init(date: String, label: String, isDeadline: Bool) {
        self.date = date
        self.label = label
        self.isDeadline = isDeadline
    }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        date = try c.decode(String.self)
        label = c.isAtEnd ? "" : try c.decode(String.self)
        isDeadline = c.isAtEnd ? false : (try c.decode(String.self)) == "deadline"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(date)
        try c.encode(label)
        if isDeadline { try c.encode("deadline") }
    }
}

enum GradeLabel {
    static func name(_ g: Int) -> String {
        switch g {
        case 0: return "Other"
        case 13: return "College"
        case 14: return "Graduate school"
        default: return "Grade \(g)"
        }
    }

    /// "Grades 9–12, college", the same wording the website uses.
    static func range(_ grades: [Int]) -> String {
        if grades.isEmpty { return "Any grade" }
        let school = grades.filter { $0 <= 12 }.sorted()
        var parts: [String] = []
        if let lo = school.first, let hi = school.last {
            parts.append(lo == hi ? "Grade \(lo)" : "Grades \(lo)–\(hi)")
        }
        if grades.contains(13) { parts.append(parts.isEmpty ? "College" : "college") }
        if grades.contains(14) { parts.append(parts.isEmpty ? "Graduate school" : "graduate school") }
        return parts.joined(separator: ", ")
    }
}
