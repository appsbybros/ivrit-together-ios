import Foundation

/// Rate, Share and Send feedback destinations. Android links to its Play Store page; on iOS
/// the App Store link needs the app's Apple ID, which the TestFlight workflow reads from
/// App Store Connect and passes in as IVRIT_APP_STORE_ID (Info.plist key IvritAppStoreID).
/// Without it (local and simulator builds), Rate asks StoreKit for the review prompt and
/// Share sends the app's name only.
enum AppLinks {
    static let appName = "Ivrit Together"
    static let feedbackAddress = "appsbybros.dev@gmail.com"

    static var appStoreID: String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "IvritAppStoreID") as? String ?? ""
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return value
    }

    static var storeURL: URL? {
        guard let id = appStoreID else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)")
    }

    static var reviewURL: URL? {
        guard let id = appStoreID else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
    }

    /// Android shares "Ivrit Together" and the store address on the next line.
    static var shareText: String {
        guard let url = storeURL else { return appName }
        return appName + "\n" + url.absoluteString
    }

    static var feedbackURL: URL? {
        URL(string: "mailto:\(feedbackAddress)?subject=Ivrit%20Together%20feedback")
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
