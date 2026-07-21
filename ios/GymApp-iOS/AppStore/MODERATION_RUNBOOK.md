# GymApp leaderboard moderation runbook

Status date: 2026-07-21

Cross-account standings are disabled in current clients. Once deployed, the
pending owner-only backend migration will prevent released clients from
discovering other profiles through the compatibility view. Keep this runbook active only for
legacy reports already in the private queue; resolve or retain them under the
documented policy. Do not reopen cross-account standings until progression comes
from a trusted server-side award source and a new abuse review is complete.

## Ownership and response target

- Queue owner: **Martynenko Eduard**
- Support contact: **support@gymapptracker.com**
- Review target: inspect unresolved legacy reports at least once every calendar
  day while any remain. Valid reports should normally receive an action within
  24 hours.
- Urgent priority: personal information, credible threats, hate/harassment, or
  repeated impersonation. Inspect these first and disable the affected profile or
  account as soon as practical.

This is a manual operational responsibility. The database safety filter and RLS
reduce risk but do not replace queue monitoring.

## Secure queue access

Use the authenticated Supabase Dashboard SQL Editor for project
`owrcbsrectdgaotndtxy`, or trusted server-side moderation tooling using a secret
key. Never place a secret/service-role key in the iOS app, browser JavaScript,
support email, screenshots, Review Notes, or this repository.

Read only the fields needed for triage:

```sql
select
  id,
  reported_profile_id,
  reported_display_name,
  reason,
  status,
  created_at
from public.leaderboard_reports
where status = 'pending'
order by created_at asc;
```

Do not export reporter UUIDs for routine name moderation. Treat every report and
identifier as private support data.

## Triage and action

1. Confirm that the current profile still exists and inspect its current filtered
   display name:

   ```sql
   select public_id, display_name
   from public.profiles
   where public_id = '<reported-profile-id>';
   ```

2. Choose one outcome:

   - **Dismissed:** the name is safe, the target no longer exists, or the report
     is clearly mistaken.
   - **Actioned:** replace an unsafe name with `GymApp user`. For repeated or
     severe abuse, locate the account in the Supabase Authentication → Users
     dashboard and ban or delete it after confirming the evidence.
   - **Reviewed:** use only when a report genuinely needs a short follow-up before
     the final action.

3. Record the decision. For a valid unsafe name, change the profile and report in
   one transaction:

   ```sql
   begin;

   update public.profiles
   set display_name = 'GymApp user'
   where public_id = '<reported-profile-id>';

   update public.leaderboard_reports
   set status = 'actioned'
   where id = '<report-id>'
     and status in ('pending', 'reviewed');

   commit;
   ```

   For a dismissed report:

   ```sql
   update public.leaderboard_reports
   set status = 'dismissed'
   where id = '<report-id>'
     and status in ('pending', 'reviewed');
   ```

4. Refresh the queue query and confirm the report is no longer pending. Never
   weaken the public display-name filter or restore anonymous/direct cross-user
   reads as a moderation shortcut.

## Reporter feedback and escalation

The app immediately confirms that a report entered the private queue. Report
status is deliberately not readable through the client API because it contains
private moderation data. A reporter who needs follow-up can contact the published
support address; verify account ownership before discussing an individual case
and never reveal another reporter's identity or internal Auth UUID.

Escalate credible threats, child-safety concerns, or unlawful content to the
appropriate platform/legal channel. Preserve only the minimum evidence needed.

## Retention

Pending reports remain until reviewed. Once a month, remove resolved reports older
than 90 days unless a legal or active-safety reason requires temporary retention:

```sql
delete from public.leaderboard_reports
where status in ('actioned', 'dismissed')
  and created_at < clock_timestamp() - interval '90 days';
```

Account/profile deletion continues to cascade related reports automatically.
Re-audit this runbook after any schema, policy, public-content, support, or staffing
change.
