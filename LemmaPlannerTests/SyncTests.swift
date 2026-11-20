import XCTest
@testable import LemmaPlanner

/// Stands in for the Lemma site: one account and what the app saved with it.
final class FakeServer: AccountServer {
    var account: AccountDetails? = AccountDetails(email: "a@example.com", grade: "10")
    var appData: AppData?
    /// Changes each time the app data is saved, like appDataAt on the site.
    var version = 0
    var saves = 0
    var sessionEnded = false
    var confirmed: [String] = []
    var badLink = false

    func fetch() async throws -> LemmaAPI.Reply {
        if sessionEnded { throw LemmaAPI.Failure(message: "Please log in again.", loggedOut: true) }
        return LemmaAPI.Reply(success: true, account: account, appData: appData, appDataAt: appData == nil ? nil : "\(version)")
    }

    func save(_ data: AppData) async throws -> LemmaAPI.Reply {
        if sessionEnded { throw LemmaAPI.Failure(message: "Please log in again.", loggedOut: true) }
        appData = data
        version += 1
        saves += 1
        return LemmaAPI.Reply(success: true, account: account, appDataAt: "\(version)")
    }

    /// Another phone or the website changed the app data.
    func changeElsewhere(_ change: (inout AppData) -> Void) {
        guard var data = appData else { return }
        change(&data)
        appData = data
        version += 1
    }

    func confirm(token: String) async throws {
        if badLink { throw LemmaAPI.Failure(message: "This link has expired or was already used.") }
        confirmed.append(token)
    }

    func logOut() async {}
}

/// Made-up programs and an AppState that touches nothing outside the test:
/// its own UserDefaults, no notifications, no cache file, no network.
@MainActor
enum Make {
    nonisolated static func program(_ id: String, title: String? = nil, grades: [Int] = [], subjects: [String] = [],
                                    body: [String] = [], timeline: [TimelineRow] = []) -> Program {
        Program(category: "competitions", id: id, title: title ?? id.capitalized, org: nil, summary: nil, body: body,
                url: nil, grades: grades, subjects: subjects, when: nil, timeline: timeline, cost: nil, format: nil, checked: nil)
    }

    nonisolated static func feed(_ programs: [Program], generated: String = "2026-10-03T00:00:00.000Z") -> ProgramFeed {
        ProgramFeed(version: 1, generated: generated,
                    subjects: [Subject(id: "biology", label: "Biology"), Subject(id: "math", label: "Math")],
                    categories: [Category(id: "competitions", label: "Competitions", note: nil)],
                    programs: programs)
    }

    static func state(server: AccountServer = FakeServer(), feed: ProgramFeed? = nil,
                      download: AppState.Download? = nil) -> AppState {
        AppState(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!, server: server,
                 feed: feed ?? Make.feed([program("alpha"), program("beta")]), cacheFile: nil, usesReminders: false,
                 download: download ?? { _ in (Data(), reply(401)) })
    }

    nonisolated static func reply(_ status: Int, tag: String? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: LemmaAPI.feed, statusCode: status, httpVersion: nil,
                        headerFields: tag.map { ["ETag": $0] })!
    }
}

@MainActor
final class SyncTests: XCTestCase {
    func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testLoginOnANewPhoneBringsTheListDown() async throws {
        let server = FakeServer()
        var profile = Profile()
        profile.grade = 11
        server.appData = AppData(profile: profile, saved: ["competitions/alpha": .applying])
        let state = Make.state(server: server)

        try await state.didLogIn()
        XCTAssertEqual(state.account?.email, "a@example.com")
        XCTAssertEqual(state.profile.grade, 11)
        XCTAssertEqual(state.saved, ["competitions/alpha": .applying])
        XCTAssertTrue(state.onboarded)

        // nothing changed on this phone, so nothing goes back up
        await state.sendUnsent()
        XCTAssertEqual(server.saves, 0)
    }

    func testAnswersGivenBeforeTheAccountGoUpAfterLogin() async throws {
        let server = FakeServer()
        let state = Make.state(server: server)
        state.profile.grade = 9
        state.profile.subjects = ["math"]
        state.onboarded = true
        await state.sendUnsent()
        XCTAssertEqual(server.saves, 0)   // no account yet

        try await state.didLogIn()
        await state.sendUnsent()
        XCTAssertEqual(server.appData?.profile.grade, 9)
        XCTAssertEqual(server.appData?.profile.subjects, ["math"])
        XCTAssertEqual(server.appData?.onboarded, true)
        XCTAssertEqual(state.profile.grade, 9)
    }

    func testAnotherAccountDoesNotGetTheFirstOnesList() async throws {
        let server = FakeServer()
        let state = Make.state(server: server)
        state.onboarded = true
        try await state.didLogIn()
        state.saved["competitions/alpha"] = .applying
        await state.sendUnsent()
        XCTAssertEqual(server.appData?.saved, ["competitions/alpha": .applying])

        // the 90-day login runs out: the phone keeps the list and carries on
        server.sessionEnded = true
        await state.sync()
        XCTAssertNil(state.account)
        XCTAssertEqual(state.saved, ["competitions/alpha": .applying])

        // someone else logs in on the same phone, with nothing saved yet
        server.sessionEnded = false
        server.account = AccountDetails(email: "b@example.com", grade: "8")
        server.appData = nil
        let before = server.saves
        try await state.didLogIn()
        await state.sendUnsent()
        XCTAssertEqual(state.account?.email, "b@example.com")
        XCTAssertEqual(state.saved, [:])
        XCTAssertFalse(state.onboarded)
        XCTAssertEqual(state.profile.grade, 8)
        XCTAssertEqual(server.saves, before)
        XCTAssertNil(server.appData)
    }

    func testTheSameAccountKeepsUnsentChangesAfterLoggingInAgain() async throws {
        let server = FakeServer()
        let state = Make.state(server: server)
        state.onboarded = true
        try await state.didLogIn()
        await state.sendUnsent()

        server.sessionEnded = true
        await state.sync()
        state.saved["competitions/beta"] = .considering   // while logged out

        server.sessionEnded = false
        try await state.didLogIn()
        await state.sendUnsent()
        XCTAssertEqual(server.appData?.saved, ["competitions/beta": .considering])
    }

    func testChangesOnBothSidesAreMerged() async throws {
        let server = FakeServer()
        let state = Make.state(server: server)
        state.onboarded = true
        try await state.didLogIn()
        await state.sendUnsent()

        // this phone saves alpha, and before that goes up another phone saves beta
        state.saved["competitions/alpha"] = .applying
        server.changeElsewhere { data in
            data.saved["competitions/beta"] = .submitted
            data.stamps = (data.stamps ?? [:]).merging(["competitions/beta": Date().timeIntervalSince1970]) { _, new in new }
        }
        await state.sync()
        let both: [String: TrackStatus] = ["competitions/alpha": .applying, "competitions/beta": .submitted]
        XCTAssertEqual(state.saved, both)
        await state.sendUnsent()
        XCTAssertEqual(server.appData?.saved, both)

        // a change made only on the other side comes down and is not sent back
        let saves = server.saves
        server.changeElsewhere { $0.saved["competitions/beta"] = .accepted }
        await state.sync()
        await state.sendUnsent()
        XCTAssertEqual(state.saved["competitions/beta"], .accepted)
        XCTAssertEqual(server.saves, saves)
    }

    func testStartOverClearsTheAccountToo() async throws {
        let server = FakeServer()
        let state = Make.state(server: server)
        state.profile.grade = 11
        state.onboarded = true
        try await state.didLogIn()
        state.saved["competitions/alpha"] = .applying
        await state.sendUnsent()

        state.resetAll()
        await state.sendUnsent()
        XCTAssertEqual(server.appData?.saved, [:])
        XCTAssertEqual(server.appData?.onboarded, false)
        XCTAssertEqual(server.appData?.profile.grade, 11)   // the grade stays
    }

    func testAsksAboutTheGradeInANewSchoolYear() {
        XCTAssertEqual(AppState.schoolYear(day(2027, 8, 31)), 2026)
        XCTAssertEqual(AppState.schoolYear(day(2027, 9, 1)), 2027)

        let state = Make.state()
        state.today = { self.day(2026, 10, 3) }
        state.profile.grade = 10
        state.onboarded = true
        XCTAssertNil(state.gradeQuestion)
        state.today = { self.day(2027, 6, 30) }
        XCTAssertNil(state.gradeQuestion)

        state.today = { self.day(2027, 9, 15) }
        XCTAssertEqual(state.gradeQuestion, 11)
        state.answerGradeQuestion(movedUp: true)
        XCTAssertEqual(state.profile.grade, 11)
        XCTAssertNil(state.gradeQuestion)

        // "no" also stops the question until the next school year
        state.today = { self.day(2028, 10, 1) }
        XCTAssertEqual(state.gradeQuestion, 12)
        state.answerGradeQuestion(movedUp: false)
        XCTAssertEqual(state.profile.grade, 11)
        XCTAssertNil(state.gradeQuestion)

        // three years on, grade 11 would be past 12: college, and then it stops asking
        state.today = { self.day(2031, 9, 1) }
        XCTAssertEqual(state.gradeQuestion, 13)
        state.answerGradeQuestion(movedUp: true)
        state.today = { self.day(2032, 9, 1) }
        XCTAssertNil(state.gradeQuestion)
    }

    func testGradesByRole() throws {
        XCTAssertEqual(Profile.grades(student: false), [6, 7, 8, 9, 10, 11, 12, 13, 0])
        XCTAssertEqual(Profile.grades(student: true), [8, 9, 10, 11, 12, 13, 0])
        XCTAssertEqual(AccountDetails.grades(role: "Parent"), ["6", "7", "8", "9", "10", "11", "12", "College", "Other"])
        XCTAssertEqual(AccountDetails.grades(role: "Student"), ["8", "9", "10", "11", "12", "College", "Other"])
        // a student account from the website keeps showing its grade
        XCTAssertEqual(AccountDetails.grades(role: "Student", keeping: "7").first, "7")
        XCTAssertEqual(AccountDetails.appGrade("6"), 6)
        XCTAssertEqual(AccountDetails.appGrade("College"), 13)
        XCTAssertEqual(AccountDetails.appGrade("Other"), 0)
        XCTAssertNil(AccountDetails.appGrade(""))
        XCTAssertNil(AccountDetails.appGrade("5"))
        XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: Data(#"{"grade":0}"#.utf8)).grade, 0)
        XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: Data(#"{"grade":5}"#.utf8)).grade, 10)
    }

    func testOtherShowsEveryGrade() {
        let state = Make.state(feed: Make.feed([Make.program("six", grades: [6]), Make.program("college", grades: [13])]))
        state.onboarded = true
        state.profile.grade = 9
        XCTAssertEqual(state.matches.count, 0)
        state.profile.grade = Profile.other
        XCTAssertEqual(state.matches.count, 2)
        // no grade to move up from
        state.today = { self.day(2030, 9, 15) }
        XCTAssertNil(state.gradeQuestion)
    }

    func testHomeScreenLists() {
        let due = { (date: String) in [TimelineRow(date: date, label: "Due", isDeadline: true)] }
        var fresh = Make.program("fresh")
        fresh.added = "2026-09-28"
        let state = Make.state(feed: Make.feed([
            Make.program("later", timeline: due("2027-02-01")),
            Make.program("sooner", timeline: due("2026-11-01")),
            Make.program("past", timeline: due("2026-09-01")),
            Make.program("undated"),
            Make.program("other-grade", grades: [6], timeline: due("2026-10-20")),
            fresh,
        ]))
        state.today = { self.day(2026, 10, 3) }
        state.profile.grade = 10

        // nothing saved: the dated programs that fit, soonest first
        XCTAssertEqual(state.nextOnList.map(\.id), ["sooner", "later"])
        XCTAssertEqual(state.comingUp, [])
        XCTAssertEqual(state.newOnList.map(\.id), ["fresh"])

        state.saved = ["competitions/later": .applying, "competitions/sooner": .submitted, "competitions/undated": .considering]
        // submitted needs no deadline any more, and undated has none
        XCTAssertEqual(state.comingUp.map(\.id), ["later"])
        XCTAssertEqual(state.nextOnList, [])
    }

    func testSearchLooksAtTheWholeListAndAtSubjectsAndText() {
        let rsi = Make.program("rsi", title: "Research Science Institute", grades: [11], subjects: ["biology"],
                               body: ["Six weeks at MIT in the summer."])
        let state = Make.state(feed: Make.feed([rsi, Make.program("alpha", grades: [9])]))
        state.profile.grade = 9
        XCTAssertEqual(state.matches.map(\.id), ["alpha"])           // the answers leave it out
        XCTAssertEqual(state.found("science inst").map(\.id), ["rsi"])
        XCTAssertEqual(state.found("MIT weeks").map(\.id), ["rsi"])    // the longer description
        XCTAssertEqual(state.found("biology").map(\.id), ["rsi"])      // a subject
        XCTAssertEqual(state.found("competitions").count, 2)           // the kind of program
        XCTAssertEqual(state.found("institute zebra"), [])
        XCTAssertEqual(state.found("  "), [])
    }

    func testListDownloadAsksOnlyForAChangedList() async throws {
        let old = Make.feed([Make.program("alpha", title: "Old name")])
        let new = Make.feed([Make.program("alpha", title: "New name")], generated: "2026-11-01T00:00:00.000Z")
        var answers: [(Data, HTTPURLResponse)] = [
            (try JSONEncoder().encode(old), Make.reply(200, tag: "\"one\"")),
            (Data(), Make.reply(304)),
            (try JSONEncoder().encode(new), Make.reply(200, tag: "\"two\"")),
            (Data(), Make.reply(304)),
        ]
        var tags: [String?] = []
        let state = Make.state(feed: old) { request in
            tags.append(request.value(forHTTPHeaderField: "If-None-Match"))
            return answers.removeFirst()
        }
        let first = await state.refresh()
        let second = await state.refresh()
        XCTAssertEqual(first, .upToDate)
        XCTAssertEqual(second, .upToDate)
        XCTAssertEqual(state.program(key: "competitions/alpha")?.title, "Old name")

        let third = await state.refresh()
        XCTAssertEqual(third, .updated)
        // what an open program page reads
        XCTAssertEqual(state.program(key: "competitions/alpha")?.title, "New name")
        _ = await state.refresh()
        XCTAssertEqual(tags, [nil, "\"one\"", "\"one\"", "\"two\""])
    }

    func testConfirmationLinkLogsIn() async {
        let link = URL(string: "https://lemmacollegecounseling.com/resources-access.html?confirm=abc123&next=resources.html")!
        XCTAssertEqual(LemmaAPI.confirmToken(in: link), "abc123")
        XCTAssertNil(LemmaAPI.confirmToken(in: URL(string: "https://lemmacollegecounseling.com/resources-access.html?reset=abc123")!))
        XCTAssertNil(LemmaAPI.confirmToken(in: URL(string: "https://lemmacollegecounseling.com/about.html?confirm=abc123")!))

        let server = FakeServer()
        let state = Make.state(server: server)
        await state.open(link: link)
        XCTAssertEqual(server.confirmed, ["abc123"])
        XCTAssertEqual(state.account?.email, "a@example.com")
        XCTAssertNil(state.linkProblem)

        let other = FakeServer()
        other.badLink = true
        let second = Make.state(server: other)
        await second.open(link: link)
        XCTAssertNil(second.account)
        XCTAssertEqual(second.linkProblem, "This link has expired or was already used.")
    }
}
