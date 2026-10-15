import Foundation

#if os(macOS)
import Darwin
import LocalAuthentication
import Security

enum KeychainAccessGate {
    /// 프로세스 전역 게이트(메모리) — 기동 시 저장값으로 1회 시드하고, 영속은
    /// UsageStore.disableKeychainAccess(didSet)가 전담한다. UserDefaults.standard 에
    /// 직접 쓰던 이전 구현은 테스트 실행이 실제 사용자 설정을 오염시켰다.
    /// (Bool 단일 플래그 — MainActor 쓰기/actor 읽기의 경합은 무해)
    nonisolated(unsafe) static var isDisabled: Bool =
        UserDefaults.standard.bool(forKey: "disableKeychainAccess")
}

/// `SecItemCopyMatching` 의 단일 통로 — 테스트가 호출 횟수를 세고(자동 폴 무접촉 단언) 항목을
/// 주입할 수 있다(실 키체인 무접촉). (upstream #221 유래, #227 테스트가 소비)
enum KeychainReader {
    nonisolated(unsafe) private(set) static var queryCount = 0
    /// 테스트가 Keychain 항목을 주입한다. 설정돼 있으면 `SecItemCopyMatching` 을 부르지 않는다.
    /// tearDown 에서 반드시 nil 로 되돌린다 — 남으면 다른 테스트가 실제 키체인을 못 본다.
    nonisolated(unsafe) static var copyMatchingForTesting: (([String: Any], inout CFTypeRef?) -> OSStatus)?

    static func resetQueryCountForTesting() { queryCount = 0 }

    static func copyMatching(_ query: [String: Any], _ result: inout CFTypeRef?) -> OSStatus {
        queryCount += 1
        if let copyMatchingForTesting {
            return copyMatchingForTesting(query, &result)
        }
        return SecItemCopyMatching(query as CFDictionary, &result)
    }
}

enum KeychainNoUIQuery {
    private static let uiFailPolicy = resolveUIFailPolicy()

    static func apply(to query: inout [String: Any]) {
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context

        // Some legacy Keychain ACL states can still prompt unless the old UI-fail
        // policy is present. Resolve it dynamically to avoid deprecated API usage.
        query[kSecUseAuthenticationUI as String] = uiFailPolicy as CFString
    }

    static func uiFailPolicyForTesting() -> String {
        uiFailPolicy
    }

    private static func resolveUIFailPolicy() -> String {
        let securityPath = "/System/Library/Frameworks/Security.framework/Security"
        guard let handle = dlopen(securityPath, RTLD_NOW) else {
            return "u_AuthUIF"
        }
        defer { dlclose(handle) }

        guard let symbol = dlsym(handle, "kSecUseAuthenticationUIFail") else {
            return "u_AuthUIF"
        }
        let valuePointer = symbol.assumingMemoryBound(to: CFString?.self)
        return (valuePointer.pointee as String?) ?? "u_AuthUIF"
    }
}
#endif
