
import SwiftUI
import SUIRA

struct StateTestView: View {
    @State private var counter: Int = 0
    @State private var textInput: String = ""
    @State private var profile = UserProfile(name: "John Doe", age: 30, email: "john@example.com")
    @StateObject private var settings = UserSettings()

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("@State Test")) {
                    StateCounterPanel(counter: $counter)
                    StateTextInputPanel(textInput: $textInput)
                    StateProfilePanel(profile: $profile)
                }

                Section(header: Text("@StateObject Test")) {
                    StateSettingsPanel(settings: settings)
                }
            }
            .navigationTitle("State Tracking Test")
            .suiraDependencyProbe("UserSettings", value: settings)
            .suiraDependencyProbe("UserProfile", value: profile)
            .trackRecomposition("StateTestView")
        }
    }
}

private struct StateCounterPanel: View {
    @Binding var counter: Int

    var body: some View {
        VStack(alignment: .leading) {
            Text("Counter: \(counter)")
                .font(.headline)

            HStack {
                Button("Decrease") {
                    counter -= 1
                }
                .buttonStyle(.bordered)

                Button("Increase") {
                    counter += 1
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 8)
        .trackRecomposition("StateTestView.Counter")
    }
}

private struct StateTextInputPanel: View {
    @Binding var textInput: String

    var body: some View {
        VStack(alignment: .leading) {
            Text("Text Input: \(textInput)")
                .font(.headline)

            TextField("Enter text", text: $textInput)
                .textFieldStyle(.roundedBorder)
                .trackRecomposition("StateTestView.TextInput.Field")
        }
        .padding(.vertical, 8)
        .trackRecomposition("StateTestView.TextInput")
    }
}

private struct StateProfilePanel: View {
    @Binding var profile: UserProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("User Profile")
                .font(.headline)

            Text("Name: \(profile.name)")
                .trackRecomposition("StateTestView.Profile.Name")
            Text("Age: \(profile.age)")
                .trackRecomposition("StateTestView.Profile.Age")
            Text("Email: \(profile.email)")
                .trackRecomposition("StateTestView.Profile.Email")

            Button("Random Profile") {
                profile = UserProfile(
                    name: ["Alice", "Bob", "Charlie"].randomElement() ?? "Unknown",
                    age: Int.random(in: 18...60),
                    email: ["a@test.com", "b@test.com", "c@test.com"].randomElement() ?? "test@test.com"
                )
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 8)
        .trackRecomposition("StateTestView.Profile")
    }
}

private struct StateSettingsPanel: View {
    @ObservedObject var settings: UserSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Username: \(settings.username)")
                .trackRecomposition("StateTestView.Settings.UsernameText")

            TextField("Username", text: $settings.username)
                .textFieldStyle(.roundedBorder)
                .trackRecomposition("StateTestView.Settings.UsernameField")

            Toggle("Logged In", isOn: $settings.isLoggedIn)
                .trackRecomposition("StateTestView.Settings.LoggedInToggle")

            HStack {
                Text("Score: \(settings.score)")
                    .trackRecomposition("StateTestView.Settings.ScoreText")
                Spacer()
                Button("Add Score") {
                    settings.score += 1
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
        .trackRecomposition("StateTestView.Settings")
    }
}

#Preview {
    StateTestView()
}
