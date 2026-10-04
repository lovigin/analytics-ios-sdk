# Lovigin Analytics for iOS

Swift package for aggregate screen-view counts. Requires iOS 15+. No third-party dependencies.

## Install with SPM

In Xcode, select **File → Add Package Dependencies**, enter:

```
https://github.com/lovigin/analytics-ios-sdk
```

Choose version **0.1.0** or later and add the `LoviginAnalytics` product to your app target. The repository must contain this package at its root and a `0.1.0` Git tag before version-based installation works.

## Configure

Create a separate project for your app in the Lovigin dashboard, verify its associated domain, and copy its complete ingestion token. The current dashboard requires a verified domain. Screen views appear in **Page views** and **Top pages** (for example `/home`).

```swift
import LoviginAnalytics

let analytics = LoviginAnalytics(
    token: "<site-id>.<ingest-key>",
    screens: ["home", "settings", "pricing"]
)
```

Keep one instance for the application. Invalid configuration returns `nil`, never crashes the app. Names are developer-defined lowercase labels, not URLs, IDs, email addresses, user input, or dynamically generated screen titles. Only listed names are counted.

An ingestion token embedded in an app is extractable. It grants write-only ingestion, not access to reports or account management. Use a dedicated project/token, rotate it if abused, and never embed an account/session credential. No SDK can hide a credential shipped inside an app.

## SwiftUI

```swift
import SwiftUI
import LoviginAnalytics

struct HomeView: View {
    let analytics: LoviginAnalytics?

    var body: some View {
        Text("Home")
            .loviginScreen("home", analytics: analytics)
    }
}
```

The modifier counts each appearance, not unique visitors. Add it once to each screen root you want measured. It does not automatically inspect navigation or screen contents.

## UIKit / manual tracking

```swift
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Task { await analytics?.trackScreen("home") }
}
```

Counts are grouped by UTC day and screen in memory and sent approximately every 15 seconds. Call `await analytics?.flush()` when the app enters background as a best-effort delivery; iOS may suspend the app before the request finishes. No background task or disk queue is created. Up to 1,000 pending views are retained, with at most 100 rows per request. Failed batches retry up to three attempts with the same request deduplication ID; crashes, suspension, offline operation, and exhausted retries can lose counts.

## Opt out

```swift
await analytics?.setCollectionEnabled(false)
```

This clears unsent counts and disables new collection for this instance. Requests already in flight cannot be recalled. The app must persist and restore its own preference if needed; the SDK stores no preference or identifier on disk.

## Data and privacy

Only UTC date, allowlisted screen label, aggregate count, and fixed event dimensions are sent. A random request ID is used only for batch deduplication, not visitor tracking. No IDFA, IDFV, installation/user/session identifier, cookies, location API, IP geolocation service, or device fingerprint is used. Country is unknown (`ZZ`); locale is not treated as location. Network infrastructure necessarily receives the connection's IP address; it is not included in the analytics payload.

The package includes `PrivacyInfo.xcprivacy` declaring unlinked Product Interaction for analytics, with no tracking and no required-reason API use. Review your app's complete App Store privacy disclosures, privacy policy, and consent obligations; the SDK does not provide a universal legal exemption or change other SDKs' requirements.

## Release

Upload the contents of this folder to the repository root (not inside another `sdk-ios` directory), run `swift test`, commit, then create and push tag `0.1.0`. Do not commit `.build`. No npm publication is needed.
