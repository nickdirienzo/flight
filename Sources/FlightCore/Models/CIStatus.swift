import Foundation

public struct CICheck: Codable {
    public let name: String
    public let state: String  // SUCCESS, FAILURE, PENDING, SKIPPED, etc.
    public let link: String?

    public init(name: String, state: String, link: String?) {
        self.name = name
        self.state = state
        self.link = link
    }
}

public struct CIStatus {
    public var checks: [CICheck]

    public init(checks: [CICheck]) {
        self.checks = checks
    }

    public var overall: CIConclusion {
        if checks.isEmpty { return .pending }
        let meaningful = checks.filter { $0.state != "SKIPPED" }
        if meaningful.isEmpty { return .success }
        if meaningful.contains(where: { $0.state == "FAILURE" }) {
            return .failure
        }
        if meaningful.allSatisfy({ $0.state == "SUCCESS" }) {
            return .success
        }
        return .pending
    }

    public var failedCheckNames: [String] {
        checks.filter { $0.state == "FAILURE" }.map(\.name)
    }

    public var passedCount: Int {
        checks.filter { $0.state == "SUCCESS" }.count
    }

    public var totalMeaningful: Int {
        checks.filter { $0.state != "SKIPPED" }.count
    }
}

public enum CIConclusion {
    case success
    case failure
    case pending
}
