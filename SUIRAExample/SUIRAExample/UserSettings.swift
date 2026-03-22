import Foundation
import SUIRA
import Combine

// Обычная модель с @Published
class UserSettings: ObservableObject {
    @Published var username: String = "Guest"
    @Published var isLoggedIn: Bool = false
    @Published var score: Int = 0
}

// Простая модель для тестирования @State
struct UserProfile {
    var name: String
    var age: Int
    var email: String
}
