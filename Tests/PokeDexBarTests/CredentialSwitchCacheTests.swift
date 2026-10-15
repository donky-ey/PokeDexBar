import XCTest
@testable import PokeDexBar

/// #227: `/login` to a second Team email rewrites `~/.claude/.credentials.json` with a
/// new still-valid token. The in-memory cache used to return the previous token until
/// `expiresAt`, so official 5h/weekly bars (and the #199 account label) stayed on the
/// old account while companion EXP kept moving from local jsonl.
///
/// These tests call the production `accessToken` path with an injected file URL.
/// Restoring the cache-before-file early return reintroduces the bug and must fail
/// `testClaudeAutoPollPicksUpInPlaceAccountSwitch` (verified by injection).
final class CredentialSwitchCacheTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-cred-switch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        KeychainReader.resetQueryCountForTesting()
    }

    override func tearDownWithError() throws {
        KeychainReader.copyMatchingForTesting = nil
        URLProtocol.unregisterClass(ClaudeUsageURLProtocol.self)
        ClaudeUsageURLProtocol.reset()
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    // MARK: Claude

    func testClaudeAutoPollPicksUpInPlaceAccountSwitch() async throws {
        let file = tempDir.appendingPathComponent("credentials.json")
        try writeClaudeCredentials(to: file, token: "token-account-a", subscription: "max")
        let cache = OAuthAccessTokenCache(credentialsFileURL: file)

        let first = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(first, "token-account-a")
        let planA = await cache.planInfo()
        XCTAssertEqual(planA.subscriptionType, "max")

        try writeClaudeCredentials(to: file, token: "token-account-b", subscription: "team")
        let second = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(
            second, "token-account-b",
            "auto-poll must re-read the credentials file; a still-unexpired cached token is the #227 bug")
        let planB = await cache.planInfo()
        XCTAssertEqual(planB.subscriptionType, "team")
        XCTAssertEqual(KeychainReader.queryCount, 0, "account switch via file must not touch Keychain")
    }

    /// File gone after a successful load (logout / CLAUDE_CONFIG_DIR leftover mop-up):
    /// keep serving the cached token on the auto path. Do not fall through to Keychain.
    func testClaudeAutoPollKeepsCacheWhenCredentialsFileDisappears() async throws {
        let file = tempDir.appendingPathComponent("credentials.json")
        try writeClaudeCredentials(to: file, token: "token-account-a", subscription: "max")
        let cache = OAuthAccessTokenCache(credentialsFileURL: file)

        _ = try await cache.accessToken(allowKeychainPrompt: false)
        try FileManager.default.removeItem(at: file)

        let stillCached = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(stillCached, "token-account-a")
        XCTAssertEqual(KeychainReader.queryCount, 0)
    }

    /// `"claudeAiOauth": null` is logout-in-place, not "no file". Must not wipe a live
    /// cache — leftover mcpOAuth-only files under the default path are why
    /// `credentialsFileIsAccountOAuthMissing` already ignores CLAUDE_CONFIG_DIR.
    func testClaudeAutoPollKeepsCacheWhenFileDropsAccountOAuth() async throws {
        let file = tempDir.appendingPathComponent("credentials.json")
        try writeClaudeCredentials(to: file, token: "token-account-a", subscription: "max")
        let cache = OAuthAccessTokenCache(credentialsFileURL: file)

        _ = try await cache.accessToken(allowKeychainPrompt: false)
        try Data(#"{"claudeAiOauth":null}"#.utf8).write(to: file)

        let stillCached = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(stillCached, "token-account-a")
        XCTAssertEqual(KeychainReader.queryCount, 0)
    }

    /// #300: Keychain-only install (no credentials file). The previous account's token is still
    /// valid, so a 401 never arrives and the in-memory cache used to answer the Refresh button
    /// forever. Restoring `bypassCache: false` on that path must fail this test.
    func testManualRefreshRereadsKeychainWhenCachedTokenIsStillValid() async throws {
        // Drives the provider's real network code against a stubbed transport (see AppEnv.allowsLiveLimitsFetch).
        AppEnv.allowLiveFetchForTesting = true
        defer { AppEnv.allowLiveFetchForTesting = false }
        let file = tempDir.appendingPathComponent("credentials.json")
        try writeClaudeCredentials(to: file, token: "token-account-a", subscription: "team")
        let cache = OAuthAccessTokenCache(credentialsFileURL: file)
        _ = try await cache.accessToken(allowKeychainPrompt: false)
        try FileManager.default.removeItem(at: file)

        let savedGate = KeychainAccessGate.isDisabled
        KeychainAccessGate.isDisabled = false
        defer { KeychainAccessGate.isDisabled = savedGate }

        KeychainReader.resetQueryCountForTesting()
        installKeychainToken("token-account-b", subscription: "team")
        URLProtocol.registerClass(ClaudeUsageURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(ClaudeUsageURLProtocol.self)
            ClaudeUsageURLProtocol.reset()
            KeychainReader.copyMatchingForTesting = nil
        }

        let provider = OAuthLimitsProvider(accessTokenCache: cache)
        _ = try await provider.fetch(allowKeychainPrompt: true)

        XCTAssertGreaterThan(KeychainReader.queryCount, 0, "Refresh must open Keychain, not the memory cache")
        XCTAssertEqual(
            ClaudeUsageURLProtocol.authorization,
            "Bearer token-account-b",
            "a still-valid cached token must not hide the account now in Keychain (#300)")

        KeychainReader.resetQueryCountForTesting()
        let auto = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(auto, "token-account-b", "user refresh should have replaced the cache")
        XCTAssertEqual(KeychainReader.queryCount, 0, "auto-poll must still not touch Keychain")
    }

    // MARK: fixtures

    private func writeClaudeCredentials(
        to url: URL, token: String, subscription: String, expiresIn: TimeInterval = 3600
    ) throws {
        let expiresAt = Int(Date().addingTimeInterval(expiresIn).timeIntervalSince1970)
        let json = """
        {"claudeAiOauth":{"accessToken":"\(token)","expiresAt":\(expiresAt),"subscriptionType":"\(subscription)"}}
        """
        try Data(json.utf8).write(to: url, options: .atomic)
    }

    private func installKeychainToken(_ token: String, subscription: String) {
        let expiresAt = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let json = """
        {"claudeAiOauth":{"accessToken":"\(token)","expiresAt":\(expiresAt),"subscriptionType":"\(subscription)"}}
        """
        let data = Data(json.utf8)
        KeychainReader.copyMatchingForTesting = { query, result in
            if (query[kSecReturnData as String] as? Bool) == true {
                result = data as CFData
                return errSecSuccess
            }
            // Accounts query must succeed. errSecItemNotFound there is "no credential",
            // not the single-item fallback (#232).
            if (query[kSecReturnAttributes as String] as? Bool) == true {
                result = [[kSecAttrAccount as String: "hello@example.com"]] as CFArray
                return errSecSuccess
            }
            return errSecItemNotFound
        }
    }
}

/// Intercepts the usage call so the Refresh path can be asserted without a live token.
private final class ClaudeUsageURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var authorization: String?

    static func reset() { authorization = nil }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.anthropic.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        if url.path == "/api/oauth/usage" {
            Self.authorization = request.value(forHTTPHeaderField: "Authorization")
            let body = Data(#"{"five_hour":{"utilization":11},"seven_day":{"utilization":22}}"#.utf8)
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
        } else {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
