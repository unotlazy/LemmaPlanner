import Foundation

/// A timeline date, written one of these ways in the data files:
///   2026-11-11                 a day
///   2027-01                    a month, when the day is not known
///   2027-06-27 to 2027-08-07   a range
///   ~2027-01-15                a leading ~ marks an estimate, usually
///                              last year's date moved forward a year
/// This follows parseWhen in resources.js on the website.
struct WhenDate: Hashable {
    var start: Date
    var end: Date
    /// The start is a whole month, not a day.
    var month: Bool
    var endMonth: Bool
    var range: Bool
    var estimated: Bool

    /// True when the date is a single known day the app can put in a calendar
    /// or remind about.
    var isExactDay: Bool { !month && !endMonth && !estimated }

    static func parse(_ raw: String, calendar: Calendar = .current) -> WhenDate? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        var estimated = false
        if s.hasPrefix("~") {
            estimated = true
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        let parts = s.components(separatedBy: " to ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count <= 2, let a = parseOne(parts[0], calendar: calendar) else { return nil }
        let b = parts.count == 2 ? parseOne(parts[1], calendar: calendar) : a
        guard let b else { return nil }
        return WhenDate(start: a.start, end: b.end, month: a.month, endMonth: b.month,
                        range: parts.count == 2, estimated: estimated)
    }

    private static func parseOne(_ s: String, calendar: Calendar) -> (start: Date, end: Date, month: Bool)? {
        let bits = s.split(separator: "-").map(String.init)
        guard bits.count == 2 || bits.count == 3,
              bits[0].count == 4, let y = Int(bits[0]),
              bits[1].count == 2, let m = Int(bits[1]), (1...12).contains(m) else { return nil }
        if bits.count == 3 {
            guard bits[2].count == 2, let d = Int(bits[2]), (1...31).contains(d),
                  let day = calendar.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
            return (day, day, false)
        }
        guard let first = calendar.date(from: DateComponents(year: y, month: m, day: 1)),
              let next = calendar.date(byAdding: .month, value: 1, to: first),
              let last = calendar.date(byAdding: .day, value: -1, to: next) else { return nil }
        return (first, last, true)
    }
}

struct Step: Hashable {
    var when: WhenDate
    var label: String
    var isDeadline: Bool
    var isPast: Bool
}

/// A program's timeline turned into sorted steps, plus its next deadline.
/// This follows schedule() in resources.js.
struct Schedule {
    enum Status { case none, open, soon, closed }

    static let soonDays = 14

    var steps: [Step]
    var next: Step?
    var status: Status

    init(_ program: Program, today: Date = Date(), calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: today)
        steps = program.timeline.compactMap { row in
            guard let w = WhenDate.parse(row.date, calendar: calendar) else { return nil }
            return Step(when: w, label: row.label, isDeadline: row.isDeadline, isPast: w.end < start)
        }
        .sorted { $0.when.start < $1.when.start }

        let deadlines = steps.filter(\.isDeadline)
        next = deadlines.first { !$0.isPast }
        if deadlines.isEmpty {
            status = .none
        } else if let next {
            let days = calendar.dateComponents([.day], from: start, to: next.when.start).day ?? 0
            status = days <= Schedule.soonDays ? .soon : .open
        } else {
            status = .closed
        }
    }

    /// Days from today to the next deadline, or nil when there is none.
    func daysToNext(today: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let next else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: next.when.start).day
    }
}

enum DateText {
    // Made once: a list of 595 rows asks for these many times per redraw.
    private static let monthYear = formatter("MMMyyyy")
    private static let dayMonthYear = formatter("MMMdyyyy")

    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static func string(_ d: Date, month: Bool) -> String {
        (month ? monthYear : dayMonthYear).string(from: d)
    }

    /// "Nov 11, 2026", "Jan 2027", "Jun 27 – Aug 7, 2027", with "about" for estimates.
    static func when(_ w: WhenDate) -> String {
        var text: String
        if !w.range {
            text = string(w.start, month: w.month)
        } else {
            let a = string(w.start, month: w.month)
            let b = string(w.end, month: w.endMonth)
            text = a + " to " + b
        }
        return w.estimated ? "About " + text : text
    }

    /// "today", "tomorrow", "in 12 days".
    static func relative(days: Int) -> String {
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        default: return "in \(days) days"
        }
    }
}

/// Finds saved programs whose upcoming deadlines are different in a new
/// program list, and says what changed in a line the family can read.
enum DateChange {
    static func find(old: ProgramFeed, new: ProgramFeed, saved: Set<String>,
                     today: Date = Date(), calendar: Calendar = .current) -> [String: String] {
        let before = Dictionary(old.programs.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [String: String] = [:]
        for p in new.programs where saved.contains(p.key) {
            guard let o = before[p.key] else { continue }
            let a = Schedule(o, today: today, calendar: calendar)
            let b = Schedule(p, today: today, calendar: calendar)
            // only deadlines still ahead: fixing a past date is not news
            let upcoming = { (s: Schedule) in s.steps.filter { $0.isDeadline && !$0.isPast }.map(\.when) }
            guard upcoming(a) != upcoming(b) else { continue }
            out[p.key] = message(was: a.next, now: b.next)
        }
        return out
    }

    static func message(was: Step?, now: Step?) -> String {
        guard let now else { return "The deadlines for this program changed." }
        let what = now.label.isEmpty ? "Deadline" : now.label
        let date = DateText.when(now.when).replacingOccurrences(of: "About ", with: "about ")
        guard let was, was.when != now.when else { return "The deadlines for this program changed. \(what) is \(date)." }
        let old = DateText.when(was.when).replacingOccurrences(of: "About ", with: "about ")
        return "\(what) is now \(date). It was \(old)."
    }
}
