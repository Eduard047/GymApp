import Foundation

/// How the watch merges a newly received context into its cached one.
enum WatchContextMerge {
    /// Unbound replaces everything (plan and catalog are dropped). An account change or a
    /// newer or equal revision replaces the plan. For the same account and a lower revision:
    /// - an empty plan is the phone's "no plan read yet" fallback: the cached plan stays,
    ///   only the catalog and language are taken;
    /// - a non-empty plan sent later than the cached context means the phone's revision
    ///   counter restarted (its plan file was cleared): the incoming plan wins;
    /// - anything else is an older message and keeps the cached plan.
    /// The device settings (`restEndAlert`) always come from the incoming context.
    static func merge(cached: WatchContextMessage?, incoming: WatchContextMessage) -> WatchContextMessage {
        guard let cached,
              let current = cached.bound,
              let next = incoming.bound,
              current.accountBinding == next.accountBinding,
              next.planRevision < current.planRevision else {
            return incoming
        }
        if !next.plan.isEmpty, incoming.sentAtMillis > cached.sentAtMillis {
            return incoming
        }
        return WatchContextMessage(
            sentAtMillis: incoming.sentAtMillis,
            bound: WatchBoundContext(
                accountBinding: next.accountBinding,
                language: next.language,
                planRevision: current.planRevision,
                plan: current.plan,
                exercises: next.exercises,
                restEndAlert: next.restEndAlert
            )
        )
    }

    /// A context from a newer phone that this watch cannot read in full. What it does
    /// understand is applied: `unbound` and an account change drop the cached plan (it must
    /// not outlive its account); the same account keeps the cached plan and catalog.
    static func merge(
        cached: WatchContextMessage?,
        header: WatchContextHeader,
        language: String,
        nowMillis: Int64
    ) -> WatchContextMessage {
        guard let binding = header.accountBinding else {
            return WatchContextMessage(sentAtMillis: nowMillis, bound: nil)
        }
        if let cached, cached.bound?.accountBinding == binding { return cached }
        return WatchContextMessage(
            sentAtMillis: nowMillis,
            bound: WatchBoundContext(accountBinding: binding, language: language, planRevision: 1, plan: [], exercises: [])
        )
    }
}
