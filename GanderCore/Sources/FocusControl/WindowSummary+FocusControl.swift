import GanderModels

extension WindowSummary {
    /// A summary of `record` on `displayID`, with an optional Accessibility title.
    init(record: WindowRecord, displayID: DisplayID, title: String?) {
        self.init(
            id: record.number,
            processID: record.processID,
            appName: record.ownerName,
            title: title,
            bounds: record.bounds,
            displayID: displayID
        )
    }

    /// This summary with `title` filled in when it is known; unchanged when `title` is `nil`.
    func settingTitle(_ title: String?) -> WindowSummary {
        guard let title else { return self }
        return WindowSummary(
            id: id,
            processID: processID,
            appName: appName,
            title: title,
            bounds: bounds,
            displayID: displayID
        )
    }
}
