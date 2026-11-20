import SwiftUI

/// Settings → Account: the details the site keeps, logging out, and deleting the account.
struct AccountView: View {
    @Environment(AppState.self) private var state
    @State private var details = AccountDetails(email: "")
    @State private var busy = false
    @State private var message: String?
    @State private var confirmLogOut = false
    @State private var askDelete = false
    @State private var deletePassword = ""

    var body: some View {
        LemmaForm {
            Section {
                LabeledContent("Email", value: details.email)
                Link("Change email or password", destination: LemmaAPI.accountPage)
            } footer: {
                Text("These change on the website. Log in there with the same account.")
            }

            Section {
                Picker("I am a", selection: $details.role) {
                    Text("Not given").tag("")
                    ForEach(AccountDetails.roles, id: \.self) { Text($0).tag($0) }
                }
                Picker("Student's grade", selection: $details.grade) {
                    Text("Not given").tag("")
                    ForEach(AccountDetails.grades, id: \.self) { Text(AccountDetails.label($0)).tag($0) }
                }
                TextField("Mobile phone (optional)", text: $details.phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                Toggle("Text me deadline reminders", isOn: $details.smsOk)
                    .disabled(details.phone.isEmpty)
                Button("Save") { Task { await save() } }
                    .disabled(busy || details == state.account)
            } footer: {
                if let message { Text(message) }
            }

            Section {
                Button("Log out") { confirmLogOut = true }
                Button("Delete account", role: .destructive) { askDelete = true }
            } footer: {
                Text("Logging out clears this phone. Your answers and saved programs stay with the account and come back when you log in. Deleting the account removes it and everything kept with it from the Lemma site.")
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(busy)
        .onAppear { if let account = state.account { details = account } }
        .confirmationDialog("Log out of \(details.email)?", isPresented: $confirmLogOut, titleVisibility: .visible) {
            Button("Log out", role: .destructive) {
                Task { busy = true; await state.logOut(); busy = false }
            }
        }
        .alert("Delete your account?", isPresented: $askDelete) {
            SecureField("Current password", text: $deletePassword)
            Button("Delete", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) { deletePassword = "" }
        } message: {
            Text("This cannot be undone. Enter your password to delete the account.")
        }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            state.accountSaved(try await LemmaAPI.save(details))
            if let account = state.account { details = account }
            message = "Saved."
        } catch {
            message = error.localizedDescription
        }
    }

    private func delete() async {
        guard !deletePassword.isEmpty else {
            message = "Enter your password to delete the account."
            return
        }
        busy = true
        defer { busy = false; deletePassword = "" }
        do {
            try await LemmaAPI.deleteAccount(password: deletePassword)
            await LemmaAPI.logOut()
            state.forgetAccount()
            state.lastEmail = ""
        } catch {
            message = error.localizedDescription
        }
    }
}
