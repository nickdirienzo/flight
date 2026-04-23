import Foundation

public struct PRReview: Codable {
    public let author: String
    public let state: String  // APPROVED, CHANGES_REQUESTED, COMMENTED, PENDING, DISMISSED

    public init(author: String, state: String) {
        self.author = author
        self.state = state
    }
}

public struct PRComment {
    public let author: String
    public let body: String
    public let path: String?
    public let line: Int?

    public init(author: String, body: String, path: String?, line: Int?) {
        self.author = author
        self.body = body
        self.path = path
        self.line = line
    }

    /// First line of the comment, trimmed
    public var summary: String {
        let first = body.components(separatedBy: "\n").first ?? body
        return first.trimmingCharacters(in: .whitespaces)
    }

    /// Whether this is an inline file comment vs a general PR comment
    public var isInline: Bool { path != nil }
}

public struct PRStatus {
    public var reviews: [PRReview]
    public var reviewDecision: String?  // APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED
    public var url: String?
    public var comments: [PRComment] = []

    public init(
        reviews: [PRReview],
        reviewDecision: String? = nil,
        url: String? = nil,
        comments: [PRComment] = []
    ) {
        self.reviews = reviews
        self.reviewDecision = reviewDecision
        self.url = url
        self.comments = comments
    }

    public var approvedBy: [String] {
        reviews.filter { $0.state == "APPROVED" }.map(\.author)
    }

    public var changesRequestedBy: [String] {
        reviews.filter { $0.state == "CHANGES_REQUESTED" }.map(\.author)
    }

    public var inlineComments: [PRComment] {
        comments.filter(\.isInline)
    }
}
