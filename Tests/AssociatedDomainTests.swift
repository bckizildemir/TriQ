import Foundation
import Testing

/// iOS offers and saves a strong password only for an app that is associated with a web domain
/// (Apple, "About the Password AutoFill workflow"). The association needs the domain in two places:
/// a `webcredentials:` entry in the app's associated domains and a `webcredentials` block in the
/// Apple App Site Association file that Hosting serves. Nothing in the app fails when they disagree
/// — the sign-up password fields just fall back to a broken strong-password sheet (#99) — so the two
/// files are asserted against each other here.
struct AssociatedDomainTests {
    @Test func theEntitlementsNameAWebCredentialsDomain() throws {
        let domains = try associatedDomains()
        let webCredentials = domains.filter { $0.hasPrefix("webcredentials:") }

        #expect(
            !webCredentials.isEmpty,
            "TTB/TTB.entitlements has no webcredentials: domain, so iOS cannot associate the app with the site for passwords"
        )
    }

    @Test func theServedAssociationFileListsThisAppForPasswords() throws {
        let apps = try webCredentialsApps()
        let appLinkApps = try appLinkAppIDs()

        #expect(
            !apps.isEmpty,
            "the served apple-app-site-association has no webcredentials.apps entry"
        )
        #expect(
            Set(apps) == Set(appLinkApps),
            "webcredentials.apps must name the same app IDs as applinks.details, found \(apps) and \(appLinkApps)"
        )
    }

    @Test func theAssociationFileSitsInTheFolderHostingServes() throws {
        let file = repoRoot
            .appending(path: try hostingPublicFolder())
            .appending(path: ".well-known/apple-app-site-association")

        #expect(
            FileManager.default.fileExists(atPath: file.path),
            "Hosting serves \(file.path), which does not exist"
        )
    }

    // MARK: - Files

    /// The checkout this test file lives in, not the test bundle: the files under test are
    /// configuration, and only the checkout holds the copy that Hosting deploys.
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func associatedDomains() throws -> [String] {
        let data = try Data(contentsOf: repoRoot.appending(path: "TTB/TTB.entitlements"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dictionary = try #require(plist as? [String: Any])

        return try #require(dictionary["com.apple.developer.associated-domains"] as? [String])
    }

    private func associationFile() throws -> [String: Any] {
        let url = repoRoot.appending(path: "Website/.well-known/apple-app-site-association")
        let data = try Data(contentsOf: url)

        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func webCredentialsApps() throws -> [String] {
        let file = try associationFile()
        let block = try #require(
            file["webcredentials"] as? [String: Any],
            "the served apple-app-site-association has no webcredentials block"
        )

        return try #require(block["apps"] as? [String])
    }

    private func appLinkAppIDs() throws -> [String] {
        let file = try associationFile()
        let appLinks = try #require(file["applinks"] as? [String: Any])
        let details = try #require(appLinks["details"] as? [[String: Any]])

        return details.flatMap { $0["appIDs"] as? [String] ?? [] }
    }

    private func hostingPublicFolder() throws -> String {
        let data = try Data(contentsOf: repoRoot.appending(path: "firebase.json"))
        let file = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hosting = try #require(file["hosting"] as? [String: Any])

        return try #require(hosting["public"] as? String)
    }
}
