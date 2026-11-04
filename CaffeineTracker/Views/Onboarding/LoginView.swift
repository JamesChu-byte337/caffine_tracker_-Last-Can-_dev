import SwiftUI

/// First screen for new users. Only uwaterloo.ca addresses are accepted; the address isn't verified yet.
struct LoginView: View {
    @Environment(ProfileStore.self) private var store
    @State private var email = ""
    @State private var showError = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image("Goose")
                .resizable()
                .scaledToFit()
                .frame(height: 120)
                .accessibilityHidden(true)
            Text("Last Can")
                .font(.largeTitle.bold())
            Text("Sign in with your University of Waterloo email to get started.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                TextField("you@uwaterloo.ca", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.continue)
                    .onSubmit(signIn)
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                if showError {
                    Text("Only @uwaterloo.ca email addresses can use Last Can right now.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Button(action: signIn) {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty)

            Text("Your email is saved only on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Spacer()
        }
        .padding(24)
        .onAppear { focused = true }
        .onChange(of: email) { showError = false }
    }

    private func signIn() {
        guard Account.isAllowed(email) else {
            showError = true
            return
        }
        store.accountEmail = Account.normalized(email)
    }
}
