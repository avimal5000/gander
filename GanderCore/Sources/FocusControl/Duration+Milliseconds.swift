extension Duration {
    /// Whole milliseconds, rounded down.
    var wholeMilliseconds: Int {
        let parts = components
        return Int(parts.seconds) * 1000 + Int(parts.attoseconds / 1_000_000_000_000_000)
    }
}
