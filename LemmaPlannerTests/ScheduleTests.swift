import XCTest
import UserNotifications
@testable import LemmaPlanner

final class ScheduleTests: XCTestCase {
    let cal = Calendar(identifier: .gregorian)

    func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func program(_ timeline: [TimelineRow], grades: [Int] = [], subjects: [String] = [],
                 category: String = "competitions", cost: String? = nil, format: String? = nil) -> Program {
        Program(category: category, id: "x", title: "X", org: nil, summary: nil, body: [], url: nil,
                grades: grades, subjects: subjects, when: nil, timeline: timeline,
                cost: cost, format: format, checked: nil)
    }

    func testParsesEveryDateForm() {
        let a = WhenDate.parse("2026-11-11", calendar: cal)!
        XCTAssertEqual(a.start, day(2026, 11, 11))
        XCTAssertTrue(a.isExactDay)

        let m = WhenDate.parse("2027-02", calendar: cal)!
        XCTAssertEqual(m.start, day(2027, 2, 1))
        XCTAssertEqual(m.end, day(2027, 2, 28))
        XCTAssertFalse(m.isExactDay)

        let r = WhenDate.parse("2027-06-27 to 2027-08-07", calendar: cal)!
        XCTAssertTrue(r.range)
        XCTAssertEqual(r.end, day(2027, 8, 7))

        let e = WhenDate.parse("~2027-01-15", calendar: cal)!
        XCTAssertTrue(e.estimated)
        XCTAssertFalse(e.isExactDay)

        XCTAssertNil(WhenDate.parse("Jan 2027", calendar: cal))
        XCTAssertNil(WhenDate.parse("", calendar: cal))
    }

    func testNewFor14DaysAfterAdded() {
        var p = program([])
        XCTAssertFalse(p.isNew(today: day(2026, 10, 3), calendar: cal))
        p.added = "2026-10-01"
        XCTAssertTrue(p.isNew(today: day(2026, 10, 1), calendar: cal))
        XCTAssertTrue(p.isNew(today: day(2026, 10, 15), calendar: cal))
        XCTAssertFalse(p.isNew(today: day(2026, 10, 16), calendar: cal))
        p.added = "2026-10"
        XCTAssertFalse(p.isNew(today: day(2026, 10, 3), calendar: cal))
    }

    func testNextDeadlineAndStatus() {
        let p = program([
            TimelineRow(date: "2026-09-01", label: "Opens", isDeadline: false),
            TimelineRow(date: "2026-10-01", label: "Early", isDeadline: true),
            TimelineRow(date: "2026-10-10", label: "Final", isDeadline: true),
        ])
        let s = Schedule(p, today: day(2026, 10, 3), calendar: cal)
        XCTAssertEqual(s.next?.label, "Final")
        XCTAssertEqual(s.status, .soon)

        XCTAssertEqual(Schedule(p, today: day(2026, 9, 1), calendar: cal).status, .open)
        XCTAssertEqual(Schedule(p, today: day(2026, 10, 11), calendar: cal).status, .closed)
        XCTAssertEqual(Schedule(program([]), today: day(2026, 10, 3), calendar: cal).status, .none)
    }

    func testMatching() {
        var profile = Profile()
        profile.grade = 10
        profile.subjects = ["math"]
        XCTAssertTrue(Matcher.matches(program([], grades: [9, 10, 11, 12], subjects: ["math", "cs"]), profile))
        XCTAssertTrue(Matcher.matches(program([], grades: [], subjects: []), profile))
        XCTAssertFalse(Matcher.matches(program([], grades: [13]), profile))
        XCTAssertFalse(Matcher.matches(program([], subjects: ["biology"]), profile))

        profile.freeOnly = true
        XCTAssertFalse(Matcher.matches(program([], cost: "$500"), profile))
        XCTAssertTrue(Matcher.matches(program([], cost: "Free to enter"), profile))
        // a program that pays the student costs nothing, and so does an unpaid internship
        XCTAssertTrue(Matcher.matches(program([], cost: "Paid stipend, housing"), profile))
        XCTAssertTrue(Matcher.matches(program([], cost: "Unpaid"), profile))
        XCTAssertTrue(Matcher.matches(program([], cost: "Usually free"), profile))
        XCTAssertFalse(Matcher.matches(program([], cost: "Tuition, aid available"), profile))
        XCTAssertFalse(Matcher.matches(program([], cost: "PSAT fee"), profile))
        // no cost listed: the app cannot tell, so it stays in
        XCTAssertTrue(Matcher.matches(program([], cost: nil), profile))

        profile.format = .online
        XCTAssertFalse(Matcher.matches(program([], cost: "Free", format: "In person, Boston"), profile))
        XCTAssertTrue(Matcher.matches(program([], cost: "Free", format: "Hybrid"), profile))
    }

    func testBundledFeedDecodes() throws {
        let url = Bundle(for: AppState.self).url(forResource: "programs", withExtension: "json")
            ?? Bundle.main.url(forResource: "programs", withExtension: "json")
        let data = try Data(contentsOf: XCTUnwrap(url))
        let feed = try JSONDecoder().decode(ProgramFeed.self, from: data)
        XCTAssertGreaterThan(feed.programs.count, 500)
        let unreadable = feed.programs.flatMap { p in p.timeline.filter { WhenDate.parse($0.date) == nil }.map { "\(p.key): \($0.date)" } }
        XCTAssertEqual(unreadable, [])
    }

    @MainActor
    func testRemindersOnlyForFutureExactDeadlines() throws {
        let contest = Make.program("contest", timeline: [
            TimelineRow(date: "2026-09-01", label: "Opens", isDeadline: false),
            TimelineRow(date: "2026-11-05", label: "First round", isDeadline: true),
            TimelineRow(date: "2027-01-20", label: "Second round", isDeadline: true),
            TimelineRow(date: "2027-03", label: "Finals", isDeadline: true),
            TimelineRow(date: "~2027-04-10", label: "Awards", isDeadline: true),
        ])
        let state = Make.state(feed: Make.feed([contest]))
        state.saved[contest.key] = .applying
        let requests = Reminders.requests(for: state, now: day(2026, 10, 3))
        // both exact deadlines get 3 reminders each, not only the next one.
        // The month and the estimate get none.
        XCTAssertEqual(requests.count, 6)
        XCTAssertEqual(Set(requests.map(\.identifier)).count, 6)

        // the last-day one fires at 9 am on the deadline itself
        let lastDay = try XCTUnwrap(requests.first { $0.identifier.hasSuffix(".0") })
        XCTAssertEqual(lastDay.content.title, "Last day: Contest")
        let fire = try XCTUnwrap((lastDay.trigger as? UNCalendarNotificationTrigger)?.dateComponents)
        XCTAssertEqual(cal.date(from: DateComponents(year: fire.year, month: fire.month, day: fire.day)), day(2026, 11, 5))
        XCTAssertEqual(fire.hour, 9)

        // 3 days before the first round, only its last day is still ahead
        XCTAssertEqual(Reminders.requests(for: state, now: day(2026, 11, 3)).count, 4)

        state.saved[contest.key] = .submitted
        XCTAssertEqual(Reminders.requests(for: state, now: day(2026, 10, 3)).count, 0)
        // an answer from the program needs no reminder either
        state.saved[contest.key] = .waitlisted
        XCTAssertEqual(Reminders.requests(for: state, now: day(2026, 10, 3)).count, 0)
    }

    func testOneBadProgramDoesNotLoseTheList() throws {
        let body = #"""
        {"version":1,"generated":"2026-10-03T00:00:00.000Z","subjects":[],"categories":[],"programs":[
          {"category":"competitions","id":"good","title":"Good","body":[],"grades":[],"subjects":[],"timeline":[["2026-11-11","Due","deadline"]]},
          {"category":"competitions","id":"bad","title":"Bad","body":[],"grades":"nine","subjects":[],"timeline":[]},
          {"category":"competitions","id":"also-good","title":"Also good","body":[],"grades":[9],"subjects":[],"timeline":[]}
        ]}
        """#
        let feed = try JSONDecoder().decode(ProgramFeed.self, from: Data(body.utf8))
        XCTAssertEqual(feed.programs.map(\.id), ["good", "also-good"])
    }

    func feed(_ programs: [Program]) -> ProgramFeed {
        ProgramFeed(version: 1, generated: "", subjects: [], categories: [], programs: programs)
    }

    func testDateChangeFindsMovedDeadlines() {
        let today = day(2026, 10, 3)
        let old = program([
            TimelineRow(date: "2026-09-01", label: "Early", isDeadline: true),
            TimelineRow(date: "~2027-01-15", label: "Application due", isDeadline: true),
        ])
        var moved = old
        moved.timeline[1].date = "2027-01-12"
        var pastFixed = old
        pastFixed.timeline[0].date = "2026-09-02"
        var renamed = old
        renamed.summary = "New summary"

        let found = DateChange.find(old: feed([old]), new: feed([moved]), saved: [old.key], today: today, calendar: cal)
        XCTAssertEqual(found[old.key], "Application due is now Jan 12, 2027. It was about Jan 15, 2027.")

        // not saved, a past date fixed, or nothing about the dates changed: no note
        XCTAssertEqual(DateChange.find(old: feed([old]), new: feed([moved]), saved: [], today: today, calendar: cal), [:])
        XCTAssertEqual(DateChange.find(old: feed([old]), new: feed([pastFixed]), saved: [old.key], today: today, calendar: cal), [:])
        XCTAssertEqual(DateChange.find(old: feed([old]), new: feed([renamed]), saved: [old.key], today: today, calendar: cal), [:])
    }

    @MainActor
    func testDateChangeNotificationOnlyForProgramsStillInProgress() throws {
        let a = Make.program("alpha"), b = Make.program("beta")
        let state = Make.state(feed: Make.feed([a, b]))
        state.saved = [a.key: .applying, b.key: .submitted]
        let changes = [a.key: "Moved.", b.key: "Moved."]

        let one = try XCTUnwrap(Reminders.announcement(changes, state: state))
        XCTAssertEqual(one.content.title, a.title)
        XCTAssertNil(one.trigger)

        state.saved[b.key] = .considering
        XCTAssertEqual(Reminders.announcement(changes, state: state)?.content.title, "Dates changed for 2 saved programs")

        state.remindersOn = false
        XCTAssertNil(Reminders.announcement(changes, state: state))
    }
}
