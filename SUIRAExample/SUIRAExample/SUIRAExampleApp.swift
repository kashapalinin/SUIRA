import SwiftUI
import SUIRA

@main
struct SUIRAExampleApp: App {

    var body: some Scene {
        WindowGroup {
            SuiraTrackedRoot {
                ExampleHubView()
            }
            .suiraInspectorOverlay()
        }
    }
}
