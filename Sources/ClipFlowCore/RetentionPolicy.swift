import Foundation

public struct RetentionCandidate: Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let byteSize: Int
    public let isFavorite: Bool

    public init(id: UUID, timestamp: Date, byteSize: Int, isFavorite: Bool) {
        self.id = id
        self.timestamp = timestamp
        self.byteSize = max(0, byteSize)
        self.isFavorite = isFavorite
    }
}

public struct RetentionPolicy: Equatable, Sendable {
    public let maxAge: TimeInterval?
    public let maxItemCount: Int?
    public let maxBytes: Int?

    public init(maxAge: TimeInterval?, maxItemCount: Int?, maxBytes: Int?) {
        self.maxAge = maxAge
        self.maxItemCount = maxItemCount
        self.maxBytes = maxBytes
    }

    public func cleanupCandidates(
        _ candidates: [RetentionCandidate],
        now: Date
    ) -> [UUID] {
        let ordered = candidates.sorted {
            if $0.timestamp != $1.timestamp {
                return $0.timestamp < $1.timestamp
            }
            return $0.id.uuidString < $1.id.uuidString
        }

        var removed = Set<UUID>()
        var removalOrder: [UUID] = []

        if let maxAge {
            let cutoff = now.addingTimeInterval(-max(0, maxAge))
            for candidate in ordered where !candidate.isFavorite && candidate.timestamp < cutoff {
                removed.insert(candidate.id)
                removalOrder.append(candidate.id)
            }
        }

        func remainingCandidates() -> [RetentionCandidate] {
            ordered.filter { !removed.contains($0.id) }
        }

        while exceedsBudget(remainingCandidates()) {
            guard let oldestRemovable = ordered.first(where: {
                !$0.isFavorite && !removed.contains($0.id)
            }) else {
                break
            }
            removed.insert(oldestRemovable.id)
            removalOrder.append(oldestRemovable.id)
        }

        return removalOrder
    }

    private func exceedsBudget(_ candidates: [RetentionCandidate]) -> Bool {
        if let maxItemCount, candidates.count > max(0, maxItemCount) {
            return true
        }

        if let maxBytes {
            let totalBytes = candidates.reduce(into: 0) { total, candidate in
                total = total.addingReportingOverflow(candidate.byteSize).overflow
                    ? Int.max
                    : total + candidate.byteSize
            }
            if totalBytes > max(0, maxBytes) {
                return true
            }
        }

        return false
    }
}
