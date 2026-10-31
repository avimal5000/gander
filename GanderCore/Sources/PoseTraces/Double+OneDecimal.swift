import Foundation

extension Double {
    /// The value with exactly one decimal digit and a `.` separator regardless of locale ("-0.0" becomes "0.0").
    var oneDecimal: String {
        let text = String(format: "%.1f", self)
        return text == "-0.0" ? "0.0" : text
    }

    /// The fraction as a percentage with one decimal and no percent sign: 0.9753 becomes "97.5".
    var percentOneDecimal: String {
        (self * 100).oneDecimal
    }
}
