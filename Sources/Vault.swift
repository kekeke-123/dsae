import Foundation
import LocalAuthentication

@MainActor
final class Vault: ObservableObject {

    enum Phase {
        case setup
        case locked
        case unlocked
    }

    @Published private(set) var phase: Phase
    @Published private(set) var password: String = ""
    @Published var faceIDEnabled: Bool {
        didSet { UserDefaults.standard.set(faceIDEnabled, forKey: Keys.faceID) }
    }
    @Published private(set) var lastPasswordDate: Date?

    private enum Keys {
        static let password = "appPassword"
        static let history = "passwordHistory"
        static let faceID = "faceIDEnabled"
        static let lastPassword = "lastPasswordDate"
    }

    static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60

    init() {
        faceIDEnabled = UserDefaults.standard.bool(forKey: Keys.faceID)
        lastPasswordDate = UserDefaults.standard.object(forKey: Keys.lastPassword) as? Date
        if SecretStore.get(Keys.password) == nil {
            phase = .setup
        } else {
            phase = .locked
        }
    }

    // MARK: - 设置 / 解锁

    func createPassword(_ value: String) -> String? {
        if let problem = PasswordPolicy.problem(with: value) { return problem }
        SecretStore.set(value, Keys.password)
        password = value
        markPasswordUsed()
        phase = .unlocked
        return nil
    }

    func unlock(with entered: String) -> String? {
        guard let stored = SecretStore.get(Keys.password) else {
            phase = .setup
            return "本机没有保存口令，请重新设置。"
        }
        guard entered == stored else { return "口令不正确。" }
        password = stored
        markPasswordUsed()
        phase = .unlocked
        return nil
    }

    func unlockWithBiometrics() async -> String? {
        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError) else {
            return "这台设备没有可用的面容 ID。"
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "用面容 ID 解锁 DSAE"
            )
            guard success else { return "面容验证未通过。" }
            guard let stored = SecretStore.get(Keys.password) else { return "本机没有保存口令。" }
            password = stored
            phase = .unlocked
            return nil
        } catch {
            return "面容验证失败，请改用口令。"
        }
    }

    // MARK: - 7 天强制口令

    var requiresPasswordRefresh: Bool {
        guard let last = lastPasswordDate else { return true }
        return Date().timeIntervalSince(last) >= Vault.refreshInterval
    }

    var daysSincePassword: Int {
        guard let last = lastPasswordDate else { return 0 }
        return Int(Date().timeIntervalSince(last) / (24 * 60 * 60))
    }

    var daysUntilRefresh: Int {
        max(0, 7 - daysSincePassword)
    }

    func markPasswordUsed() {
        let now = Date()
        lastPasswordDate = now
        UserDefaults.standard.set(now, forKey: Keys.lastPassword)
    }

    // MARK: - 修改口令

    func changePassword(to newValue: String) -> String? {
        if let problem = PasswordPolicy.problem(with: newValue) { return problem }
        guard let old = SecretStore.get(Keys.password) else { return "本机没有保存口令。" }
        if old == newValue { return "新口令和当前口令相同。" }
        var history = PasswordHistory.load()
        history.append(old)
        PasswordHistory.save(history)
        SecretStore.set(newValue, Keys.password)
        password = newValue
        markPasswordUsed()
        return nil
    }

    func encryptionCandidates() -> [String] {
        let history = PasswordHistory.load()
        return [password] + history
    }

    func lock() {
        password = ""
        phase = .locked
    }
}

enum PasswordHistory {

    private static let key = "passwordHistory"
    private static let limit = 5

    static func load() -> [String] {
        guard let raw = SecretStore.get(key),
              let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return list
    }

    static func save(_ list: [String]) {
        let trimmed = Array(list.suffix(limit))
        guard let data = try? JSONEncoder().encode(trimmed),
              let raw = String(data: data, encoding: .utf8) else { return }
        SecretStore.set(raw, key)
    }
}
