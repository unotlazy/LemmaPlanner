import Foundation
import Observation

/// Where a family is with a program they saved.
enum TrackStatus: String, Codable, CaseIterable, Identifiable {
    // In the order the Saved tab lists them.
    case considering, applying, submitted, waitlisted, accepted, rejected, declined
    var id: String { rawValue }
    var label: String {
        switch self {
        case .considering: return "Considering"
        case .applying: return "Applying"
        case .submitted: return "Submitted"
        case .waitlisted: return "Waitlisted"
        case .accepted: return "Accepted"
        case .rejected: return "Not accepted"
        case .declined: return "Turned down the offer"
        }
    }
    var symbol: String {
        switch self {
        case .considering: return "bookmark"
        case .applying: return "pencil.line"
        case .submitted: return "paperplane"
        case .waitlisted: return "clock"
        case .accepted: return "checkmark.seal"
        case .rejected: return "xmark.circle"
        case .declined: return "arrow.uturn.left.circle"
        }
    }
    /// Reminders only make sense before the application is in.
    var wantsReminders: Bool { self == .considering || self == .applying }
}

/// Everything the app keeps: the program list, the account, the answers, and saved programs.
/// The answers and saved programs live in UserDefaults and are kept in step
/// with the Lemma account: changes here go up, and changes made on another
/// phone or on the website come down when the app opens.
@MainActor
@Observable
final class AppState {
    /// What a download of the program list came to.
    enum RefreshResult { case updated, upToDate, failed }
    typealias Download = (URLRequest) async throws -> (Data, URLResponse)

    var feed: ProgramFeed? { didSet { lookup = nil } }
    var lastRefresh: Date?
    /// A confirmation link that did not work, for the app to show.
    var linkProblem: String?

    var profile: Profile {
        didSet {
            save(profile, "profile")
            guard profile != oldValue else { return }
            if !applyingRemote {
                profileAt = Date().timeIntervalSince1970
                if profile.grade != oldValue.grade { gradeYear = Self.schoolYear(today()) }
            }
            changed()
        }
    }
    var onboarded: Bool {
        didSet {
            defaults.set(onboarded, forKey: "onboarded")
            // the questions ask for this school year's grade
            if onboarded, !applyingRemote { gradeYear = Self.schoolYear(today()) }
            changed()
        }
    }
    var saved: [String: TrackStatus] {
        didSet {
            save(saved, "saved")
            guard saved != oldValue else { return }
            if !applyingRemote {
                // note when each program changed, so a merge with another phone can go program by program
                let now = Date().timeIntervalSince1970
                for key in Set(saved.keys).union(oldValue.keys) where saved[key] != oldValue[key] { stamps[key] = now }
            }
            reminders?.reschedule(self)
            changed()
        }
    }
    /// The logged-in account, or nil. The app works without one: the list and
    /// the answers need no account. Saving a program asks for one.
    var account: AccountDetails? {
        didSet {
            save(account, "account")
            if let account { lastEmail = account.email; dataOwner = account.email.lowercased() }
        }
    }
    /// Fills in the login form after logging out or when the session runs out.
    var lastEmail: String { didSet { defaults.set(lastEmail, forKey: "lastEmail") } }
    var remindersOn: Bool { didSet { defaults.set(remindersOn, forKey: "remindersOn"); reminders?.reschedule(self) } }
    /// Saved programs whose deadlines moved in a new list, with a line saying
    /// what changed. Shown on the program until the family opens it.
    var dateChanges: [String: String] { didSet { save(dateChanges, "dateChanges") } }

    /// The clock. The tests set it to try a later school year.
    @ObservationIgnored var today: () -> Date = { Date() }

    private let defaults: UserDefaults
    private let server: AccountServer
    private let download: Download
    /// Where a downloaded list is kept. Nil in the tests, so they write no file.
    private let cacheFile: URL?
    /// False in the tests, so they set no notifications on the simulator.
    private let usesReminders: Bool
    private var reminders: Reminders? { usesReminders ? .shared : nil }
    private var uploadTask: Task<Void, Never>?
    /// Changes on this phone that have not reached the account yet.
    private var unsent: Bool { didSet { defaults.set(unsent, forKey: "unsent") } }
    /// The site's appDataAt from the last upload or download. When the site
    /// has a different one, someone changed the answers somewhere else.
    private var syncedAt: String? { didSet { defaults.set(syncedAt, forKey: "syncedAt") } }
    /// When the answers and each saved program last changed on a phone. See AppData.
    private var profileAt: Double? { didSet { defaults.set(profileAt, forKey: "profileAt") } }
    private var stamps: [String: Double] { didSet { save(stamps, "stamps") } }
    /// The email of the account that the answers and saved programs on this
    /// phone belong to. Empty when nobody has logged in since the phone was
    /// last cleared, so what is here was made without an account.
    private var dataOwner: String { didSet { defaults.set(dataOwner, forKey: "dataOwner") } }
    /// The school year the grade is for. See AppData.
    private(set) var gradeYear: Int? { didSet { defaults.set(gradeYear, forKey: "gradeYear") } }
    /// The ETag the site sent with the last list the app read, so the next
    /// download can ask for the list only if it changed.
    private var feedTag: String? { didSet { defaults.set(feedTag, forKey: "feedTag") } }
    /// Schedules and search text for the current list, worked out once a day.
    @ObservationIgnored private var lookup: Lookup?
    /// The last `matches`, kept until the answers or the list change.
    @ObservationIgnored private var lastMatches: (profile: Profile, list: [Program])?
    /// Counts changes, so an upload that finishes after a newer change does not mark it sent.
    private var changeCount = 0
    /// True while copying in what came from the site, so that is not sent straight back.
    private var applyingRemote = false

    init(defaults: UserDefaults = .standard, server: AccountServer = LiveServer(),
         feed: ProgramFeed? = nil, cacheFile: URL? = AppState.defaultCacheFile, usesReminders: Bool = true,
         download: @escaping Download = { try await URLSession.shared.data(for: $0) }) {
        self.defaults = defaults
        self.server = server
        self.download = download
        self.cacheFile = cacheFile
        self.usesReminders = usesReminders
        profile = Self.load(Profile.self, "profile", defaults) ?? Profile()
        onboarded = defaults.bool(forKey: "onboarded")
        saved = Self.load([String: TrackStatus].self, "saved", defaults) ?? [:]
        remindersOn = defaults.object(forKey: "remindersOn") as? Bool ?? true
        account = Self.load(AccountDetails.self, "account", defaults)
        lastEmail = defaults.string(forKey: "lastEmail") ?? ""
        unsent = defaults.bool(forKey: "unsent")
        syncedAt = defaults.string(forKey: "syncedAt")
        dataOwner = defaults.string(forKey: "dataOwner") ?? ""
        profileAt = defaults.object(forKey: "profileAt") as? Double
        stamps = Self.load([String: Double].self, "stamps", defaults) ?? [:]
        dateChanges = Self.load([String: String].self, "dateChanges", defaults) ?? [:]
        gradeYear = defaults.object(forKey: "gradeYear") as? Int
        feedTag = defaults.string(forKey: "feedTag")
        self.feed = feed ?? Self.loadLocalFeed(cacheFile)
    }

    var programs: [Program] { feed?.programs ?? [] }
    var subjects: [Subject] { feed?.subjects ?? [] }
    var categories: [Category] { feed?.categories ?? [] }

    func subjectLabel(_ id: String) -> String { subjects.first { $0.id == id }?.label ?? id }
    func categoryLabel(_ id: String) -> String { categories.first { $0.id == id }?.label ?? id }
    func program(key: String) -> Program? { lookups().byKey[key] }

    /// Things worked out from the list that every row and every search
    /// keystroke would otherwise work out again.
    private struct Lookup {
        var day: Date
        var byKey: [String: Program]
        var schedules: [String: Schedule]
        /// Everything search looks in, in lower case, by program key.
        var searchText: [String: String]
    }

    /// Built again when the list changes (`feed` clears it) or the day does,
    /// since a schedule depends on today's date.
    private func lookups() -> Lookup {
        let day = Calendar.current.startOfDay(for: today())
        let programs = self.programs   // read first, so a view that only uses the lookups still follows the list
        if let lookup, lookup.day == day { return lookup }
        var fresh = Lookup(day: day, byKey: [:], schedules: [:], searchText: [:])
        for p in programs where fresh.byKey[p.key] == nil {
            fresh.byKey[p.key] = p
            fresh.schedules[p.key] = Schedule(p, today: day)
            let words = [p.title, p.org, p.summary, p.format, p.when, p.cost, categoryLabel(p.category)].compactMap { $0 }
                + p.body + p.subjects.map(subjectLabel)
            fresh.searchText[p.key] = Self.fold(words.joined(separator: "\n"))
        }
        lookup = fresh
        lastMatches = nil
        return fresh
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    /// The program's steps and next deadline as of today.
    func schedule(for p: Program) -> Schedule {
        lookups().schedules[p.key] ?? Schedule(p, today: today())
    }

    private func sorted(_ list: [Program]) -> [Program] {
        let look = lookups()
        return Matcher.sorted(list, today: today()) { look.schedules[$0.key] ?? Schedule($0, today: look.day) }
    }

    /// The family's list: programs that fit the answers, by next deadline.
    var matches: [Program] {
        let look = lookups()
        if let last = lastMatches, last.profile == profile { return last.list }
        let all = programs.filter { Matcher.matches($0, profile) }
        let shown = profile.showClosed ? all : all.filter { look.schedules[$0.key]?.status != .closed }
        let list = sorted(shown)
        lastMatches = (profile, list)
        return list
    }

    /// Every program on the whole list with all the words of `text` in its
    /// name, organisation, description, subjects, kind, cost, format or
    /// timing. The answers do not narrow it, so a family can find a program
    /// by name even when it does not fit them.
    func found(_ text: String) -> [Program] {
        let words = Self.fold(text).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }
        let look = lookups()
        return sorted(programs.filter { p in
            guard let hay = look.searchText[p.key] else { return false }
            return words.allSatisfy { hay.contains($0) }
        })
    }

    var savedPrograms: [Program] { sorted(programs.filter { saved[$0.key] != nil }) }

    /// How many saved programs are in the list now. `saved` can also hold
    /// programs that a later list dropped.
    var savedCount: Int { programs.filter { saved[$0.key] != nil }.count }

    /// Saved programs that are no longer in the list, by key.
    var missingSaved: [String] {
        guard !programs.isEmpty else { return [] }
        let known = Set(programs.map(\.key))
        return saved.keys.filter { !known.contains($0) }.sorted()
    }

    func removeMissingSaved() {
        let gone = Set(missingSaved)
        guard !gone.isEmpty else { return }
        saved = saved.filter { !gone.contains($0.key) }
        for key in gone { dateChanges[key] = nil }
    }

    func toggleSaved(_ p: Program) {
        if saved[p.key] == nil {
            saved[p.key] = .considering
            reminders?.askPermissionIfNeeded(self)
        } else {
            saved[p.key] = nil
            dateChanges[p.key] = nil
        }
    }

    /// The family opened the program, so the note about its dates has been read.
    func seenDateChange(_ p: Program) {
        if dateChanges[p.key] != nil { dateChanges[p.key] = nil }
    }

    /// Start over: clears the answers and saved programs and asks the
    /// questions again. The cleared state goes up to the account too. The
    /// grade stays, because the site copies it to the account's grade.
    func resetAll() {
        var fresh = Profile()
        fresh.grade = profile.grade
        saved = [:]
        dateChanges = [:]
        profile = fresh
        onboarded = false
    }

    // MARK: grade

    /// The school year a day is in, named by the year it starts: September
    /// 2026 to August 2027 is 2026.
    static func schoolYear(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.year, .month], from: date)
        let year = parts.year ?? 0
        return (parts.month ?? 1) >= 9 ? year : year - 1
    }

    /// The grade the student should be in by now, when a new school year
    /// started since the grade was last set. Nil when there is nothing to
    /// ask. The app asks before changing it: a student can repeat or skip a
    /// year, and the website can change the grade without the year.
    var gradeQuestion: Int? {
        guard onboarded, profile.grade < 13, let year = gradeYear else { return nil }
        let passed = Self.schoolYear(today()) - year
        return passed > 0 ? min(profile.grade + passed, 13) : nil
    }

    /// The family answered the question. Either answer stops it until the next school year.
    func answerGradeQuestion(movedUp: Bool) {
        let next = gradeQuestion
        gradeYear = Self.schoolYear(today())
        if movedUp, let next { profile.grade = next } else { changed() }
    }

    /// Answers from before the app kept the school year, or made on the
    /// website, have none. They count as this year's.
    func fillGradeYear() {
        if onboarded, gradeYear == nil { gradeYear = Self.schoolYear(today()) }
    }

    /// Empties this phone without sending anything to the account.
    private func clearLocal() {
        uploadTask?.cancel()
        applyingRemote = true
        saved = [:]
        dateChanges = [:]
        profile = Profile()
        onboarded = false
        applyingRemote = false
        stamps = [:]
        profileAt = nil
        unsent = false
        syncedAt = nil
        dataOwner = ""
        gradeYear = nil
    }

    // MARK: account

    /// After a login: the answers and saved programs kept with the account
    /// come down to this phone. Answers given here before there was an
    /// account are merged in and go up. When the 90-day login ran out the
    /// phone still has that account's list, which is kept only if the same
    /// account logs in again.
    func didLogIn() async throws {
        let reply = try await server.fetch()
        guard let details = reply.account else {
            throw LemmaAPI.Failure(message: "The Lemma site sent an answer the app could not read. Please try again later.")
        }
        if !dataOwner.isEmpty, dataOwner != details.email.lowercased() { clearLocal() }
        if reply.appData == nil, !onboarded, let grade = AccountDetails.appGrade(details.grade) {
            // not a change by the family, so it does not count as one
            applyingRemote = true
            profile.grade = grade
            applyingRemote = false
        }
        merge(reply)
        await refresh()
    }

    /// Each time the app opens or comes back to the front: picks up changes
    /// made on the website or another phone, and sends this phone's changes.
    func sync() async {
        guard account != nil else { return }
        do {
            merge(try await server.fetch())
        } catch let failure as LemmaAPI.Failure where failure.loggedOut {
            // the 90-day login ran out: the app carries on without the account,
            // and Saved and Settings ask the family to log in again
            account = nil
        } catch {
            // offline: carry on with what is on the phone
        }
    }

    /// The family opened the link from a confirmation email on this phone.
    /// The site confirms the address and logs the account in, so the app
    /// does not need the password again. Other links are left alone.
    func open(link url: URL) async {
        guard let token = LemmaAPI.confirmToken(in: url) else { return }
        do {
            try await server.confirm(token: token)
            try await didLogIn()
        } catch {
            linkProblem = error.localizedDescription
        }
    }

    /// Settings → Account saved new details. The site copies a new grade into
    /// the app data, so it comes back here too.
    func accountSaved(_ reply: LemmaAPI.Reply) {
        if let details = reply.account { account = details }
        if let grade = AccountDetails.appGrade(account?.grade ?? ""), grade != profile.grade {
            profile.grade = grade
        }
    }

    /// Takes what the site sent. When this phone also has changes that have
    /// not gone up, the two are merged program by program and the result
    /// goes up next.
    private func merge(_ reply: LemmaAPI.Reply) {
        if let details = reply.account { account = details }
        if let remote = reply.appData, reply.appDataAt != syncedAt {
            let data = unsent ? AppData.merged(local: currentData, remote: remote) : remote
            applyingRemote = true
            profile = data.profile
            saved = data.saved
            onboarded = data.onboarded ?? true
            applyingRemote = false
            profileAt = data.profileAt
            stamps = data.stamps ?? [:]
            gradeYear = [gradeYear, data.gradeYear].compactMap { $0 }.max()
            syncedAt = reply.appDataAt
        } else if reply.appData == nil, onboarded {
            unsent = true
        }
        fillGradeYear()
        if unsent { uploadSoon() }
    }

    /// What goes up to the account. Times of removed programs are dropped
    /// after 180 days.
    private var currentData: AppData {
        let cutoff = Date().timeIntervalSince1970 - 180 * 86400
        let kept = stamps.filter { saved[$0.key] != nil || $0.value > cutoff }
        return AppData(profile: profile, saved: saved, onboarded: onboarded, profileAt: profileAt, stamps: kept, gradeYear: gradeYear)
    }

    func logOut() async {
        await sendUnsent()
        await server.logOut()
        forgetAccount()
    }

    /// Sends what is waiting now, without the 2 second wait.
    func sendUnsent() async {
        uploadTask?.cancel()
        await upload()
    }

    /// Clears this phone after logging out or deleting the account.
    func forgetAccount() {
        account = nil
        clearLocal()
    }

    /// Without an account the change waits here and goes up after a login.
    private func changed() {
        guard !applyingRemote else { return }
        changeCount += 1
        unsent = true
        uploadSoon()
    }

    /// Waits 2 seconds so a run of taps sends one upload.
    private func uploadSoon() {
        guard account != nil, unsent else { return }
        uploadTask?.cancel()
        uploadTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await upload()
        }
    }

    private func upload() async {
        guard account != nil, unsent else { return }
        let sending = changeCount
        do {
            let reply = try await server.save(currentData)
            if changeCount == sending { unsent = false }
            syncedAt = reply.appDataAt
            // the site sets the account's grade from the answers
            if let details = reply.account { account = details }
        } catch {
            // stays unsent: the next change or the next time the app opens sends it again
        }
    }

    // MARK: program list

    nonisolated static var defaultCacheFile: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("programs.json")
    }

    /// The newer of the copy shipped in the app and the last one downloaded.
    private static func loadLocalFeed(_ cacheFile: URL?) -> ProgramFeed? {
        let decoder = JSONDecoder()
        let bundled = Bundle.main.url(forResource: "programs", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? decoder.decode(ProgramFeed.self, from: $0) }
        let cached = cacheFile.flatMap { try? Data(contentsOf: $0) }.flatMap { try? decoder.decode(ProgramFeed.self, from: $0) }
        switch (bundled, cached) {
        case let (b?, c?): return c.generated > b.generated ? c : b
        case let (b, c): return c ?? b
        }
    }

    /// Coming back to the app: downloads the list again unless that happened
    /// in the last 15 minutes, so switching apps does not fetch it every time.
    func refreshIfStale() async {
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < 15 * 60 { return }
        await refresh()
    }

    /// Downloads the latest list from the Lemma site. Keeps the current list
    /// when there is no connection or the file is missing. The list is about
    /// 350 KB, so the app sends the ETag of the last one it read and the site
    /// answers 304 with no body when nothing changed.
    @discardableResult
    func refresh() async -> RefreshResult {
        do {
            var request = URLRequest(url: LemmaAPI.feed)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15
            if let feedTag { request.setValue(feedTag, forHTTPHeaderField: "If-None-Match") }
            let (data, response) = try await download(request)
            let http = response as? HTTPURLResponse
            if http?.statusCode == 304 { lastRefresh = Date(); return .upToDate }
            guard http?.statusCode == 200 else { return .failed }
            let tag = http?.value(forHTTPHeaderField: "ETag")
            let fresh = try JSONDecoder().decode(ProgramFeed.self, from: data)
            if let current = feed, fresh.generated <= current.generated {
                feedTag = tag
                lastRefresh = Date()
                return .upToDate
            }
            // Unreadable programs are skipped. A list that lost more than half
            // of them is broken, so the current one stays.
            guard !fresh.programs.isEmpty, fresh.programs.count * 2 >= programs.count else { return .failed }
            if let cacheFile { try data.write(to: cacheFile, options: .atomic) }
            feedTag = tag
            let changes = feed.map { DateChange.find(old: $0, new: fresh, saved: Set(saved.keys)) } ?? [:]
            feed = fresh
            lastRefresh = Date()
            reminders?.reschedule(self)
            if !changes.isEmpty {
                dateChanges.merge(changes) { _, new in new }
                reminders?.announce(changes, state: self)
            }
            return .updated
        } catch {
            // Offline or a bad file: keep what we have.
            return .failed
        }
    }

    // MARK: storage

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
