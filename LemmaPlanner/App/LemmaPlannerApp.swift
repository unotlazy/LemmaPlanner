import SwiftUI
import UserNotifications

@main
struct LemmaPlannerApp: App {
    @State private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        Brand.styleNavigationBars()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .linkProblemAlert()
                .tint(Color("AccentColor"))
                .environment(state)
                // on launch and when coming back to the app: set the reminders
                // again, since a deadline may have passed and the next one needs
                // its own. Then pick up changes made on the website, then a newer
                // program list. The list needs the login cookie, so it waits for
                // the sync.
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active {
                        state.fillGradeYear()
                        Reminders.shared.reschedule(state)
                        Task {
                            await state.sync()
                            await state.refreshIfStale()
                        }
                    }
                }
                // the link in a confirmation email, when iOS opens it in the app
                .onOpenURL { url in
                    Task { await state.open(link: url) }
                }
        }
    }
}

extension View {
    /// Says why a confirmation link did not work. On the root view and on the
    /// account sheet, because an alert under a sheet does not show.
    func linkProblemAlert() -> some View { modifier(LinkProblemAlert()) }
}

private struct LinkProblemAlert: ViewModifier {
    @Environment(AppState.self) private var state

    func body(content: Content) -> some View {
        content.alert("That link did not work", isPresented: Binding(
            get: { state.linkProblem != nil },
            set: { if !$0 { state.linkProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.linkProblem ?? "")
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        // The account comes first: nothing else shows until the family has
        // created one or logged in. Then the questions, then the app.
        if state.account == nil {
            AccountGate()
        } else if state.onboarded {
            MainTabs()
        } else {
            OnboardingView()
        }
    }
}

struct MainTabs: View {
    @Environment(AppState.self) private var state
    @State private var tab = Tab.home
    @State private var savedPath: [Program] = []

    enum Tab { case home, plan, saved, settings }

    var body: some View {
        let presenter = NotificationPresenter.shared
        TabView(selection: $tab) {
            HomeView(tab: $tab)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Tab.home)
            PlanView()
                .tabItem { Label("My list", systemImage: "list.bullet.rectangle") }
                .tag(Tab.plan)
            SavedView(path: $savedPath)
                .tabItem { Label("Saved", systemImage: "bookmark") }
                .badge(state.savedCount)
                .tag(Tab.saved)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        // A tapped reminder opens its program in Saved. The one about several
        // programs opens Saved itself.
        .onChange(of: presenter.tap, initial: true) { _, tap in
            guard let tap else { return }
            tab = .saved
            savedPath = tap.key.flatMap(state.program(key:)).map { [$0] } ?? []
            presenter.tap = nil
        }
    }
}
