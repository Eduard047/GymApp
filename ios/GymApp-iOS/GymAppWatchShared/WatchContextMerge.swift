import Foundation

/// How the watch merges a newly received context into its cached one.
enum WatchContextMerge {
    /// Unbound replaces everything (plan and catalog are dropped). A bound context
    /// for the same account with an older plan revision keeps the cached plan but
    /// takes the newer catalog and language; an account change or a newer revision replaces the plan.
    static func merge(cached: WatchContextMessage?, incoming: WatchContextMessage) -> WatchContextMessage {
        guard let current = cached?.bound,
              let next = incoming.bound,
              current.accountBinding == next.accountBinding,
              next.planRevision < current.planRevision else {
            return incoming
        }
        return WatchContextMessage(
            sentAtMillis: incoming.sentAtMillis,
            bound: WatchBoundContext(
                accountBinding: next.accountBinding,
                language: next.language,
                planRevision: current.planRevision,
                plan: current.plan,
                exercises: next.exercises
            )
        )
    }
}
