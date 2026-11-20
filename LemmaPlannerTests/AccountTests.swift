import XCTest
@testable import LemmaPlanner

final class AccountTests: XCTestCase {
    /// The site keeps app data as Postgres jsonb, which reorders keys, so the
    /// app has to read back what the site returns, not only what it sent.
    func testAppDataComesBackFromTheSite() throws {
        var profile = Profile()
        profile.grade = 11
        profile.subjects = ["math", "cs"]
        profile.format = .online
        let sent = AppData(profile: profile, saved: ["competitions/amc": .applying])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sent))
        let fromSite = try JSONSerialization.data(withJSONObject: ["success": true, "appData": json], options: .sortedKeys)

        let reply = try JSONDecoder().decode(LemmaAPI.Reply.self, from: fromSite)
        XCTAssertEqual(reply.appData?.profile, profile)
        XCTAssertEqual(reply.appData?.saved, ["competitions/amc": .applying])
    }

    func testAccountWithNoAppDataYet() throws {
        let body = #"{"success":true,"account":{"email":"a@b.co","role":"Parent","grade":"10","phone":"","smsOk":false,"pendingEmail":"","since":"2026-10-03T00:00:00Z"},"appData":null}"#
        let reply = try JSONDecoder().decode(LemmaAPI.Reply.self, from: Data(body.utf8))
        XCTAssertEqual(reply.account, AccountDetails(email: "a@b.co", role: "Parent", grade: "10"))
        XCTAssertNil(reply.appData)
    }

    /// The website writes the app data too, and may leave fields out or use
    /// values this version of the app does not know.
    func testReadsAppDataWithMissingAndUnknownFields() throws {
        let body = #"{"success":true,"account":{"email":"a@b.co"},"appData":{"profile":{"grade":11,"format":"weekends","subjects":["math"]},"saved":{"competitions/amc":"deferred","research/rsi":"submitted"}},"appDataAt":"2026-11-01T00:00:00Z"}"#
        let reply = try JSONDecoder().decode(LemmaAPI.Reply.self, from: Data(body.utf8))
        XCTAssertEqual(reply.account, AccountDetails(email: "a@b.co"))
        let data = try XCTUnwrap(reply.appData)
        XCTAssertEqual(data.profile.grade, 11)
        XCTAssertEqual(data.profile.subjects, ["math"])
        XCTAssertEqual(data.profile.format, .any)
        XCTAssertFalse(data.profile.showClosed)
        XCTAssertEqual(data.saved, ["competitions/amc": .considering, "research/rsi": .submitted])
        XCTAssertNil(data.onboarded)
    }

    func testMergeGoesProgramByProgram() {
        var mine = Profile()
        mine.grade = 11
        var theirs = Profile()
        theirs.grade = 9
        // this phone saved A at 200 and removed C at 300; the other phone
        // saved B at 250, moved A on at 100 and still has C from 50
        let local = AppData(profile: mine, saved: ["x/a": .applying, "x/web-local": .considering],
                            profileAt: 400, stamps: ["x/a": 200, "x/c": 300])
        let remote = AppData(profile: theirs, saved: ["x/a": .submitted, "x/b": .considering, "x/c": .accepted, "x/web": .considering],
                             profileAt: 350, stamps: ["x/a": 100, "x/b": 250, "x/c": 50])
        let out = AppData.merged(local: local, remote: remote)
        XCTAssertEqual(out.saved, [
            "x/a": .applying,           // later change here wins
            "x/b": .considering,        // saved on the other phone
            "x/web": .considering,      // saved on the website, which keeps no time
            "x/web-local": .considering
        ])
        XCTAssertNil(out.saved["x/c"])  // removed here after the other phone last touched it
        XCTAssertEqual(out.stamps?["x/c"], 300)
        XCTAssertEqual(out.profile.grade, 11)

        // answers changed later on the other phone
        var newer = remote
        newer.profileAt = 500
        XCTAssertEqual(AppData.merged(local: local, remote: newer).profile.grade, 9)
    }

    func testCollegeIsGrade13() {
        XCTAssertEqual(AccountDetails.appGrade("College"), 13)
        XCTAssertEqual(AccountDetails.appGrade("9"), 9)
        XCTAssertNil(AccountDetails.appGrade(""))
        XCTAssertNil(AccountDetails.appGrade("5"))
        XCTAssertEqual(AccountDetails.label("College"), "College")
        XCTAssertEqual(AccountDetails.label("11"), "Grade 11")
    }
}
