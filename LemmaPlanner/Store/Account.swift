import Foundation

/// The account details the Lemma site keeps: the same accounts as the
/// Resources pages on lemmacollegecounseling.com.
struct AccountDetails: Codable, Equatable {
    var email: String
    /// "Parent", "Student" or "".
    var role: String = ""
    /// "6" to "12", "College", or "".
    var grade: String = ""
    var phone: String = ""
    var smsOk: Bool = false

    static let roles = ["Parent", "Student"]
    static let grades = Array(6...12).map(String.init) + ["College"]

    static func label(_ grade: String) -> String { grade == "College" ? grade : "Grade \(grade)" }

    /// The site's grade as the app keeps it: 6 to 12, or 13 for college.
    static func appGrade(_ grade: String) -> Int? {
        grade == "College" ? 13 : Int(grade).flatMap { (6...12).contains($0) ? $0 : nil }
    }
}

extension AccountDetails {
    /// Only the email has to be there.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        email = try c.decode(String.self, forKey: .email)
        role = (try? c.decode(String.self, forKey: .role)) ?? ""
        grade = (try? c.decode(String.self, forKey: .grade)) ?? ""
        phone = (try? c.decode(String.self, forKey: .phone)) ?? ""
        smsOk = (try? c.decode(Bool.self, forKey: .smsOk)) ?? false
    }
}

/// What the app saves with the account, so a family's list comes back on a new phone.
/// The site keeps the whole thing as it is, and the website changes `profile`
/// and `saved` in it without touching the other fields.
struct AppData: Codable {
    var version = 1
    var profile: Profile
    var saved: [String: TrackStatus]
    /// False after Start over, until the questions are answered again.
    /// Missing means true: the website never writes it.
    var onboarded: Bool?
    /// When the answers last changed on a phone, in seconds since 1970.
    var profileAt: Double?
    /// When each program was last saved, changed or removed on a phone.
    /// A removed program keeps its time here so the removal can win a merge.
    var stamps: [String: Double]?
    /// The school year the grade is for: 2026 means September 2026 to August
    /// 2027. The app asks about the grade again when a later one starts.
    var gradeYear: Int?
}

extension AppData {
    /// Reads what it can. A status the app does not know counts as considering,
    /// so the program stays saved.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        profile = (try? c.decode(Profile.self, forKey: .profile)) ?? Profile()
        let raw = (try? c.decode([String: String].self, forKey: .saved)) ?? [:]
        saved = raw.mapValues { TrackStatus(rawValue: $0) ?? .considering }
        onboarded = try? c.decode(Bool.self, forKey: .onboarded)
        profileAt = try? c.decode(Double.self, forKey: .profileAt)
        stamps = try? c.decode([String: Double].self, forKey: .stamps)
        gradeYear = try? c.decode(Int.self, forKey: .gradeYear)
    }

    /// For when this phone and the site both changed since they last agreed.
    /// For each program the later change wins, and so do the later answers.
    /// A program with no time on either side is kept if either side has it:
    /// the website saves programs without a time.
    static func merged(local: AppData, remote: AppData) -> AppData {
        var out = local
        if (remote.profileAt ?? 0) > (local.profileAt ?? 0) {
            out.profile = remote.profile
            out.profileAt = remote.profileAt
        }
        let mine = local.stamps ?? [:], theirs = remote.stamps ?? [:]
        var saved: [String: TrackStatus] = [:]
        var stamps: [String: Double] = [:]
        let keys = Set(local.saved.keys).union(remote.saved.keys).union(mine.keys).union(theirs.keys)
        for key in keys {
            let a = mine[key] ?? 0, b = theirs[key] ?? 0
            if a == 0 && b == 0 {
                saved[key] = local.saved[key] ?? remote.saved[key]
            } else if b > a {
                saved[key] = remote.saved[key]
                stamps[key] = b
            } else {
                saved[key] = local.saved[key]
                stamps[key] = a
            }
        }
        out.saved = saved
        out.stamps = stamps
        out.gradeYear = [local.gradeYear, remote.gradeYear].compactMap { $0 }.max()
        return out
    }
}

/// The calls AppState makes to the Lemma site. The tests put a stand-in here.
protocol AccountServer {
    func fetch() async throws -> LemmaAPI.Reply
    func save(_ data: AppData) async throws -> LemmaAPI.Reply
    func confirm(token: String) async throws
    func logOut() async
}

/// The real site.
struct LiveServer: AccountServer {
    func fetch() async throws -> LemmaAPI.Reply { try await LemmaAPI.fetch() }
    func save(_ data: AppData) async throws -> LemmaAPI.Reply { try await LemmaAPI.save(data) }
    func confirm(token: String) async throws { try await LemmaAPI.confirm(token: token) }
    func logOut() async { await LemmaAPI.logOut() }
}

/// Calls /api/account on the Lemma site. Logging in sets the site's
/// lemma_session cookie, which URLSession keeps in HTTPCookieStorage for
/// 90 days, the same as a browser. That cookie also unlocks programs.json.
enum LemmaAPI {
    static var base: URL {
        #if DEBUG
        // For testing against `npm run dev` on this Mac: LEMMA_API_BASE=http://localhost:3000
        if let s = ProcessInfo.processInfo.environment["LEMMA_API_BASE"], let url = URL(string: s) { return url }
        #endif
        return Brand.site
    }

    /// Terms of Use and Privacy Policy on the site, which registering agrees to.
    static var terms: URL { base.appendingPathComponent("terms.html") }
    static var privacy: URL { base.appendingPathComponent("privacy.html") }
    /// The program list. It follows LEMMA_API_BASE too, so a test against
    /// this Mac reads this Mac's list.
    static var feed: URL { base.appendingPathComponent("programs.json") }
    /// The shortest password the site takes.
    static let passwordLength = 8
    /// Where to change the email or password; the site asks for a login there.
    static var accountPage: URL { base.appendingPathComponent("account.html") }

    struct Failure: LocalizedError {
        var message: String
        /// The email is not confirmed yet.
        var unconfirmed = false
        /// The login cookie is missing or expired.
        var loggedOut = false
        var errorDescription: String? { message }
    }

    /// The fields the site sends back. Each call fills only some of them.
    struct Reply: Decodable {
        var success: Bool?
        var message: String?
        var unconfirmed: Bool?
        var loggedOut: Bool?
        var account: AccountDetails?
        var appData: AppData?
        /// When the site last saved appData. It only changes when something
        /// saves the app data, so the app compares it with the last one it saw.
        var appDataAt: String?
    }

    static func register(_ details: AccountDetails, password: String) async throws {
        _ = try await send("register", [
            "email": details.email, "password": password,
            "role": details.role, "grade": details.grade,
            "phone": details.phone, "smsOk": details.smsOk && !details.phone.isEmpty,
            "agree": true, "datesOk": true,
            "source": "Lemma Planner iOS app"
        ])
    }

    static func logIn(email: String, password: String) async throws {
        _ = try await send("login", ["email": email, "password": password])
    }

    /// Uses the token from the link in a confirmation email. The site
    /// confirms the address and logs the account in.
    static func confirm(token: String) async throws {
        _ = try await send("confirm", ["token": token])
    }

    /// The token, when the address is a confirmation link from a Lemma email:
    /// https://lemmacollegecounseling.com/resources-access.html?confirm=<token>
    static func confirmToken(in url: URL) -> String? {
        guard url.path == "/resources-access.html",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let token = items.first(where: { $0.name == "confirm" })?.value, !token.isEmpty else { return nil }
        return token
    }

    static func resendConfirmation(email: String) async throws -> String {
        try await send("confirm", ["email": email]).message ?? "We have sent a new link."
    }

    static func sendPasswordReset(email: String) async throws -> String {
        try await send("reset", ["email": email]).message ?? "We have sent a link to reset the password."
    }

    /// The account details and what the app saved last, if anything.
    static func fetch() async throws -> Reply {
        try await send(nil, nil)
    }

    /// Also copies a new grade into the app data on the site.
    static func save(_ details: AccountDetails) async throws -> Reply {
        try await send(nil, [
            "action": "profile", "role": details.role, "grade": details.grade,
            "phone": details.phone, "smsOk": details.smsOk && !details.phone.isEmpty
        ])
    }

    /// Also sets the account's grade from the answers.
    static func save(_ data: AppData) async throws -> Reply {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(data))
        return try await send(nil, ["action": "appdata", "data": json])
    }

    static func deleteAccount(password: String) async throws {
        _ = try await send(nil, ["action": "delete", "current": password])
    }

    static func logOut() async {
        _ = try? await send("logout", nil)
        let storage = HTTPCookieStorage.shared
        storage.cookies(for: base)?.forEach(storage.deleteCookie)
    }

    /// GET when there is no body, POST with JSON otherwise.
    private static func send(_ op: String?, _ body: [String: Any]?) async throws -> Reply {
        var parts = URLComponents(url: base.appendingPathComponent("api/account"), resolvingAgainstBaseURL: false)!
        if let op { parts.queryItems = [URLQueryItem(name: "op", value: op)] }
        var request = URLRequest(url: parts.url!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure(message: "Could not reach the Lemma site. Check the connection and try again.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // logout ends on the site's sign-in page, which is HTML
        if op == "logout" { return Reply() }
        let decoded = try? JSONDecoder().decode(Reply.self, from: data)
        let reply = decoded ?? Reply()
        guard (200..<300).contains(status), reply.success != false else {
            throw Failure(
                message: reply.message ?? "That did not go through. Please try again.",
                unconfirmed: reply.unconfirmed == true,
                loggedOut: reply.loggedOut == true || status == 401 && op == nil
            )
        }
        // An answer the app cannot read must not pass for an empty one: the
        // app would take it to mean the account has nothing saved.
        guard decoded != nil else {
            throw Failure(message: "The Lemma site sent an answer the app could not read. Please try again later.")
        }
        return reply
    }
}
