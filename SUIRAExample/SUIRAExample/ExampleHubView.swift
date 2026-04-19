import SwiftUI

struct ExampleHubView: View {
    var body: some View {
        NavigationView {
            List {
                Section("Тестовые экраны") {
                    NavigationLink("State Tracking Test") {
                        StateTestView()
                    }

                    NavigationLink("Feed Recomposition Test") {
                        FeedRecompositionTestView()
                    }
                }
            }
            .navigationTitle("SUIRA Example")
        }
    }
}

#Preview {
    ExampleHubView()
}
