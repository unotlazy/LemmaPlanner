import SwiftUI

/// Create a Lemma account or log in with one made on the website. Shown as a
/// sheet when the family saves a program without an account, and from the
/// first screen and Settings. It closes itself once they are logged in.
struct AccountGate: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Step] = []

    enum Step: Hashable {
        case register
        case logIn
        /// After registering: the password is kept only in memory, so
        /// Continue can log in once the email is confirmed.
        case checkEmail(email: String, password: String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 16) {
                LemmaLogo(height: 64)
                    .padding(.top, 8)
                Text("Your Lemma account")
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                Text("Saving programs needs a free account. Your answers and saved programs are kept with it, so they come back if you get a new phone, and deadline reminders can reach you by email.")
                    .foregroundStyle(.secondary)
                Text("It is the same account as the Resources pages on lemmacollegecounseling.com. If you already made one there, log in with it.")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button {
                    path.append(.register)
                } label: {
                    Text("Create an account").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button {
                    path.append(.logIn)
                } label: {
                    Text("I already have an account").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(24)
            .background(Brand.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .register:
                    RegisterView { email, password in path.append(.checkEmail(email: email, password: password)) }
                case .logIn:
                    LogInView()
                case let .checkEmail(email, password):
                    CheckEmailView(email: email, password: password)
                }
            }
        }
        .onAppear {
            // The login ran out or the family logged out: go straight to logging in.
            if !state.lastEmail.isEmpty && path.isEmpty { path = [.logIn] }
        }
        .onChange(of: state.account != nil) { _, loggedIn in
            if loggedIn { dismiss() }
        }
        .linkProblemAlert()
    }
}

struct RegisterView: View {
    @Environment(AppState.self) private var state
    let done: (_ email: String, _ password: String) -> Void

    @State private var details = AccountDetails(email: "")
    @State private var password = ""
    @State private var agree = false
    @State private var datesOk = false
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        LemmaForm {
            Section {
                TextField("Email", text: $details.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password, at least \(LemmaAPI.passwordLength) characters", text: $password)
                    .textContentType(.newPassword)
            } footer: {
                if !password.isEmpty && password.count < LemmaAPI.passwordLength {
                    Text("The password needs at least \(LemmaAPI.passwordLength) characters.")
                }
            }

            Section {
                Picker("I am a", selection: $details.role) {
                    Text("Choose").tag("")
                    ForEach(AccountDetails.roles, id: \.self) { Text($0).tag($0) }
                }
                Picker("Student's grade", selection: $details.grade) {
                    Text("Choose").tag("")
                    ForEach(AccountDetails.grades, id: \.self) { Text(AccountDetails.label($0)).tag($0) }
                }
            }

            Section {
                TextField("Mobile phone (optional)", text: $details.phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                Toggle("Text me deadline reminders", isOn: $details.smsOk)
                    .disabled(details.phone.isEmpty)
            }

            Section {
                HStack {
                    Link("Terms of Use", destination: LemmaAPI.terms)
                    Spacer()
                    Link("Privacy Policy", destination: LemmaAPI.privacy)
                }
                .font(.subheadline)
                Toggle(isOn: $agree) {
                    Text(ageLine + " I agree to the Terms of Use and Privacy Policy.")
                        .font(.subheadline)
                }
                if details.role == "Student" {
                    Text("Students under 13 cannot make an account. If you are under 13, ask a parent or guardian to create it and choose Parent above.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Toggle(isOn: $datesOk) {
                    Text("I understand that dates, deadlines and other details can change or contain mistakes. I will confirm them on each program's official page, and I will not hold Lemma College Counseling responsible for missed deadlines or errors.")
                        .font(.subheadline)
                }
            }

            Section {
                Button {
                    Task { await register() }
                } label: {
                    HStack {
                        Text("Create account")
                        if busy { Spacer(); ProgressView() }
                    }
                }
                .disabled(busy || !agree || !datesOk || details.role.isEmpty || details.email.isEmpty || password.count < LemmaAPI.passwordLength)
            } footer: {
                if let problem { Text(problem).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Create an account")
        .navigationBarTitleDisplayMode(.inline)
        // the tick box says something different for a parent and a student, so it has to be ticked again
        .onChange(of: details.role) { agree = false }
        .onAppear {
            // the grade from the questions, when they were answered first
            if details.grade.isEmpty, state.onboarded {
                details.grade = state.profile.grade == 13 ? "College" : String(state.profile.grade)
            }
        }
    }

    /// What the person ticking the box says about their age. The app serves
    /// grades 6 and 7, where many students are under 13, so a student and a
    /// parent each get their own sentence.
    private var ageLine: String {
        switch details.role {
        case "Student": return "I am the student and I am at least 13 years old."
        case "Parent": return "I am the student's parent or guardian."
        default: return "I am at least 13 years old, or I am the student's parent or guardian."
        }
    }

    private func register() async {
        busy = true
        defer { busy = false }
        problem = nil
        details.email = details.email.trimmingCharacters(in: .whitespaces)
        do {
            try await LemmaAPI.register(details, password: password)
            // so the login form has the email if the app is closed before the address is confirmed
            state.lastEmail = details.email
            done(details.email, password)
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// Waits for the family to open the link in the confirmation email.
struct CheckEmailView: View {
    @Environment(AppState.self) private var state
    let email: String
    let password: String

    @State private var busy = false
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 56)).foregroundStyle(Brand.gold)
                .padding(.top, 40)
            Text("Check your email")
                .font(.system(.largeTitle, design: .serif).weight(.semibold))
            Text("We sent a link to \(email). Open it to confirm your address. If the link opens this app, you are done. If it opens the website, come back here and tap Continue. The link works for 48 hours.")
                .foregroundStyle(.secondary)
            Text("Can't find it? Look in the spam folder too.")
                .font(.footnote).foregroundStyle(.secondary)
            if let note { Text(note).font(.callout) }
            Spacer()
            Button {
                Task { await logIn() }
            } label: {
                HStack {
                    Spacer()
                    Text("Continue")
                    if busy { ProgressView().padding(.leading, 8) }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(busy)
            Button {
                Task { await resend() }
            } label: {
                Text("Send the link again").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(busy)
        }
        .padding(24)
        .background(Brand.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func logIn() async {
        busy = true
        defer { busy = false }
        do {
            try await LemmaAPI.logIn(email: email, password: password)
            try await state.didLogIn()
        } catch let failure as LemmaAPI.Failure where failure.unconfirmed {
            note = "Your email is not confirmed yet. Open the link in the email first."
        } catch {
            note = error.localizedDescription
        }
    }

    private func resend() async {
        busy = true
        defer { busy = false }
        note = (try? await LemmaAPI.resendConfirmation(email: email)) ?? "We could not send the email. Please try again."
    }
}

struct LogInView: View {
    @Environment(AppState.self) private var state
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var problem: String?
    @State private var note: String?
    @State private var unconfirmed = false

    var body: some View {
        LemmaForm {
            Section {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
            } footer: {
                Text("Use the email and password from the Resources pages on lemmacollegecounseling.com.")
            }

            Section {
                Button {
                    Task { await logIn() }
                } label: {
                    HStack {
                        Text("Log in")
                        if busy { Spacer(); ProgressView() }
                    }
                }
                .disabled(busy || email.isEmpty || password.isEmpty)
                if unconfirmed {
                    Button("Send the confirmation link again") { Task { await resend() } }
                        .disabled(busy)
                }
                Button("Forgot your password?") { Task { await reset() } }
                    .disabled(busy)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let problem { Text(problem).foregroundStyle(.red) }
                    if let note { Text(note) }
                }
            }
        }
        .navigationTitle("Log in")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if email.isEmpty { email = state.lastEmail } }
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }

    private func logIn() async {
        busy = true
        defer { busy = false }
        problem = nil
        note = nil
        do {
            try await LemmaAPI.logIn(email: trimmedEmail, password: password)
            try await state.didLogIn()
        } catch let failure as LemmaAPI.Failure {
            unconfirmed = failure.unconfirmed
            problem = failure.message
        } catch {
            problem = error.localizedDescription
        }
    }

    private func resend() async {
        busy = true
        defer { busy = false }
        do {
            note = try await LemmaAPI.resendConfirmation(email: trimmedEmail)
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    /// The link opens the website, where the new password is set. Then log in here with it.
    private func reset() async {
        guard !trimmedEmail.isEmpty else { problem = "Enter your email first."; return }
        busy = true
        defer { busy = false }
        do {
            note = try await LemmaAPI.sendPasswordReset(email: trimmedEmail) + " After you choose the new password, log in here with it."
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }
}
