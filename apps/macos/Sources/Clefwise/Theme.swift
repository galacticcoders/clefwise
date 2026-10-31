import SwiftUI

enum Theme {
    static let paper = Color(red: 0.992, green: 0.984, blue: 0.965)
    static let ink = Color(red: 0.12, green: 0.11, blue: 0.10)
    static let accent = Color(red: 0.23, green: 0.31, blue: 0.63)
    static let correct = Color(red: 0.18, green: 0.58, blue: 0.35)
    /// `correct` at ~12% over white, opaque so keys don't show the background through.
    static let correctTint = Color(red: 0.90, green: 0.95, blue: 0.92)
    static let wrong = Color(red: 0.83, green: 0.27, blue: 0.24)
    static let hint = Color(red: 0.42, green: 0.49, blue: 0.66)
    static let keyBorder = Color(red: 0.80, green: 0.82, blue: 0.87)
    static let background = LinearGradient(
        colors: [Color(red: 0.94, green: 0.95, blue: 0.97), Color(red: 0.88, green: 0.91, blue: 0.95)],
        startPoint: .top,
        endPoint: .bottom
    )
}
