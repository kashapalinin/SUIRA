
import SwiftUI
import SUIRA

struct StateTestView: View {
    // MARK: - Properties

    // @State для тестирования
    @State private var counter: Int = 0
    @State private var textInput: String = ""
    @State private var profile = UserProfile(name: "John Doe", age: 30, email: "john@example.com")
    
    // @StateObject для тестирования
    @StateObject private var settings = UserSettings()
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            List {
                // Секция с @State
                Section(header: Text("@State Test")) {
                    // Счетчик
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

                    // Текстовое поле
                    VStack(alignment: .leading) {
                        Text("Text Input: \(textInput)")
                            .font(.headline)
                        
                        TextField("Enter text", text: $textInput)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 8)
                    
                    // Профиль
                    VStack(alignment: .leading, spacing: 8) {
                        Text("User Profile")
                            .font(.headline)
                        
                        Text("Name: \(profile.name)")
                        Text("Age: \(profile.age)")
                        Text("Email: \(profile.email)")
                        
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
                }
                
                // Секция с @StateObject
                Section(header: Text("@StateObject Test")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Username: \(settings.username)")
                        
                        TextField("Username", text: $settings.username)
                            .textFieldStyle(.roundedBorder)
                        
                        Toggle("Logged In", isOn: $settings.isLoggedIn)
                        
                        HStack {
                            Text("Score: \(settings.score)")
                            Spacer()
                            Button("Add Score") {
                                settings.score += 1
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("State Tracking Test")
            .suiraDependencyProbe("UserSettings", value: settings)
            .suiraDependencyProbe("UserProfile", value: profile)
            // Один раз на экран: трекер должен быть внутри этого View — иначе при @State обновляется только body экрана, а не обёртка из App.
            .trackRecomposition("StateTestView")
        }
    }
}

#Preview {
    StateTestView()
}
