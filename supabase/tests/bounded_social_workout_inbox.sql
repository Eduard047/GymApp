begin;

select plan(34);

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values
  (
    '00000000-0000-0000-0000-000000000000',
    'f1000000-0000-4000-8000-000000000001',
    'authenticated', 'authenticated', 'inbox-sender-a@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'f1000000-0000-4000-8000-000000000002',
    'authenticated', 'authenticated', 'inbox-sender-b@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'f1000000-0000-4000-8000-000000000003',
    'authenticated', 'authenticated', 'inbox-recipient@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'f1000000-0000-4000-8000-000000000004',
    'authenticated', 'authenticated', 'inbox-outsider@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

insert into auth.sessions (id, user_id, created_at, updated_at) values
  ('f2000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001', pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()),
  ('f2000000-0000-4000-8000-000000000002', 'f1000000-0000-4000-8000-000000000002', pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()),
  ('f2000000-0000-4000-8000-000000000003', 'f1000000-0000-4000-8000-000000000003', pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()),
  ('f2000000-0000-4000-8000-000000000004', 'f1000000-0000-4000-8000-000000000004', pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp());

insert into public.profiles (
  user_id, public_id, display_name, xp, level, workouts,
  progression_version, updated_at
) values
  ('f1000000-0000-4000-8000-000000000001', 'p_10000000000000000000000000000001', 'Sender A', 0, 1, 0, 1, pg_catalog.clock_timestamp()),
  ('f1000000-0000-4000-8000-000000000002', 'p_10000000000000000000000000000002', 'Sender B', 0, 1, 0, 1, pg_catalog.clock_timestamp()),
  ('f1000000-0000-4000-8000-000000000003', 'p_10000000000000000000000000000003', 'Recipient', 0, 1, 0, 1, pg_catalog.clock_timestamp()),
  ('f1000000-0000-4000-8000-000000000004', 'p_10000000000000000000000000000004', 'Outsider', 0, 1, 0, 1, pg_catalog.clock_timestamp());

insert into gymapp_private.friendships (
  id, user_low_id, user_high_id, requester_user_id, status,
  revision, requested_at, responded_at, updated_at
) values
  (
    'f_10000000000000000000000000000001',
    'f1000000-0000-4000-8000-000000000001',
    'f1000000-0000-4000-8000-000000000003',
    'f1000000-0000-4000-8000-000000000001',
    'accepted', 2,
    pg_catalog.clock_timestamp() - interval '2 days',
    pg_catalog.clock_timestamp() - interval '1 day',
    pg_catalog.clock_timestamp() - interval '1 day'
  ),
  (
    'f_10000000000000000000000000000002',
    'f1000000-0000-4000-8000-000000000002',
    'f1000000-0000-4000-8000-000000000003',
    'f1000000-0000-4000-8000-000000000002',
    'accepted', 2,
    pg_catalog.clock_timestamp() - interval '2 days',
    pg_catalog.clock_timestamp() - interval '1 day',
    pg_catalog.clock_timestamp() - interval '1 day'
  );

with fixture as (
  select
    series.number,
    pg_catalog.clock_timestamp()
      - pg_catalog.make_interval(mins => series.number) as created_at
  from pg_catalog.generate_series(1, 12) as series(number)
)
insert into gymapp_private.social_workout_invites (
  id, sender_user_id, recipient_user_id, client_request_id, status,
  workout, summary, revision, created_at, expires_at, responded_at, updated_at
)
select
  'wi_' || pg_catalog.lpad(pg_catalog.to_hex(fixture.number), 32, '0'),
  'f1000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000003',
  pg_catalog.gen_random_uuid(),
  'pending',
  '{"version":1,"exercises":[{"name":"Bench press","sets":[{"weight":20,"reps":10}]}]}'::jsonb,
  '{"exerciseCount":1,"setCount":1,"exerciseNames":["Bench press"]}'::jsonb,
  1,
  fixture.created_at,
  fixture.created_at + interval '7 days',
  null,
  fixture.created_at
from fixture;

with fixture as (
  select
    series.number,
    pg_catalog.clock_timestamp()
      - pg_catalog.make_interval(secs => series.number::double precision) as created_at
  from pg_catalog.generate_series(101, 103) as series(number)
)
insert into gymapp_private.social_workout_invites (
  id, sender_user_id, recipient_user_id, client_request_id, status,
  workout, summary, revision, created_at, expires_at, responded_at, updated_at
)
select
  'wi_' || pg_catalog.lpad(pg_catalog.to_hex(fixture.number), 32, '0'),
  'f1000000-0000-4000-8000-000000000002',
  'f1000000-0000-4000-8000-000000000003',
  pg_catalog.gen_random_uuid(),
  'accepted',
  '{"version":1,"exercises":[{"name":"Row","sets":[{"weight":25,"reps":8}]}]}'::jsonb,
  '{"exerciseCount":1,"setCount":1,"exerciseNames":["Row"]}'::jsonb,
  2,
  fixture.created_at,
  fixture.created_at + interval '7 days',
  fixture.created_at + interval '1 second',
  fixture.created_at + interval '1 second'
from fixture;

set local request.jwt.claim.sub = 'f1000000-0000-4000-8000-000000000003';
set local request.jwt.claims =
  '{"sub":"f1000000-0000-4000-8000-000000000003","role":"authenticated","session_id":"f2000000-0000-4000-8000-000000000003"}';

create temporary table bounded_inbox_results (
  page_number integer primary key,
  payload jsonb not null
) on commit drop;

insert into bounded_inbox_results (page_number, payload)
values (1, public.social_workout_inbox_page(null, null, null, 10));

insert into bounded_inbox_results (page_number, payload)
select
  2,
  public.social_workout_inbox_page(
    (first.payload #>> '{nextCursor,createdAt}')::timestamptz,
    first.payload #>> '{nextCursor,inviteId}',
    (first.payload #>> '{nextCursor,pending}')::boolean,
    10
  )
from bounded_inbox_results as first
where first.page_number = 1;

select is(
  (select payload->>'version' from bounded_inbox_results where page_number = 1),
  '2',
  'metadata inbox uses version 2'
);
select is(
  (select pg_catalog.jsonb_array_length(payload->'incoming')
    from bounded_inbox_results where page_number = 1),
  10,
  'first page is bounded to the requested row count'
);
select ok(
  not exists (
    select 1
    from bounded_inbox_results as result,
      lateral pg_catalog.jsonb_array_elements(result.payload->'incoming') as invite(value)
    where result.page_number = 1
      and invite.value->>'status' <> 'pending'
  ),
  'pending invites remain ahead of newer accepted history'
);
select ok(
  not exists (
    select 1
    from bounded_inbox_results as result,
      lateral pg_catalog.jsonb_array_elements(result.payload->'incoming') as invite(value)
    where invite.value ? 'workout'
  ),
  'neither page repeats a private workout payload'
);
select is(
  (select payload->>'pendingIncomingCount'
    from bounded_inbox_results where page_number = 1),
  '12',
  'pending count is independent from page size'
);
select is(
  (select payload #>> '{nextCursor,pending}'
    from bounded_inbox_results where page_number = 1),
  'true',
  'cursor preserves the pending-priority tuple'
);
select ok(
  (select pg_catalog.octet_length(
      pg_catalog.convert_to(payload::text, 'UTF8')
    ) <= 258048
    from bounded_inbox_results where page_number = 1),
  'response stays inside the shared client byte limit'
);
select is(
  (select pg_catalog.jsonb_array_length(payload->'incoming')
    from bounded_inbox_results where page_number = 2),
  5,
  'second page contains every remaining eligible invite'
);
select is(
  (select payload #>> '{incoming,0,status}'
    from bounded_inbox_results where page_number = 2),
  'pending',
  'second page drains remaining pending invites first'
);
select is(
  (select payload #>> '{incoming,2,status}'
    from bounded_inbox_results where page_number = 2),
  'accepted',
  'accepted history follows the pending invites'
);
select ok(
  not exists (
    select first_invite.value->>'inviteId'
    from bounded_inbox_results as first_result,
      lateral pg_catalog.jsonb_array_elements(first_result.payload->'incoming') as first_invite(value)
    join bounded_inbox_results as second_result on second_result.page_number = 2
    cross join lateral pg_catalog.jsonb_array_elements(second_result.payload->'incoming') as second_invite(value)
    where first_result.page_number = 1
      and first_invite.value->>'inviteId' = second_invite.value->>'inviteId'
  ),
  'stable cursor does not repeat an invite'
);
select is(
  (select payload->'nextCursor' from bounded_inbox_results where page_number = 2),
  'null'::jsonb,
  'last page has no continuation cursor'
);
select is(
  public.social_workout_invite_plan(
    'wi_00000000000000000000000000000001', 1
  ) #>> '{workout,exercises,0,name}',
  'Bench press',
  'recipient can fetch exactly one matching-revision plan'
);
select throws_ok(
  $$select public.social_workout_invite_plan(
    'wi_00000000000000000000000000000001', 2
  )$$,
  'P0002',
  'Social resource unavailable.',
  'a stale plan revision fails without an existence oracle'
);
select throws_ok(
  $$select public.social_workout_inbox_page(null, null, true, 10)$$,
  '22023',
  'Workout inbox page is invalid.',
  'partial cursors are rejected'
);

delete from gymapp_private.social_workout_invites
where recipient_user_id = 'f1000000-0000-4000-8000-000000000003';

with fixture as (
  select
    series.number,
    pg_catalog.clock_timestamp() - interval '36 days'
      + pg_catalog.make_interval(mins => series.number) as created_at
  from pg_catalog.generate_series(201, 212) as series(number)
)
insert into gymapp_private.social_workout_invites (
  id, sender_user_id, recipient_user_id, client_request_id, status,
  workout, summary, revision, created_at, expires_at, responded_at, updated_at
)
select
  'wi_' || pg_catalog.lpad(pg_catalog.to_hex(fixture.number), 32, '0'),
  'f1000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000003',
  pg_catalog.gen_random_uuid(),
  'accepted',
  '{"version":1,"exercises":[{"name":"Late acceptance","sets":[{"weight":20,"reps":10}]}]}'::jsonb,
  '{"exerciseCount":1,"setCount":1,"exerciseNames":["Late acceptance"]}'::jsonb,
  2,
  fixture.created_at,
  fixture.created_at + interval '7 days',
  fixture.created_at + interval '7 days',
  fixture.created_at + interval '7 days'
from fixture;

create temporary table late_acceptance_inbox_results (
  page_number integer primary key,
  payload jsonb not null
) on commit drop;

insert into late_acceptance_inbox_results (page_number, payload)
values (1, public.social_workout_inbox_page(null, null, null, 10));

insert into late_acceptance_inbox_results (page_number, payload)
select
  2,
  public.social_workout_inbox_page(
    (first.payload #>> '{nextCursor,createdAt}')::timestamptz,
    first.payload #>> '{nextCursor,inviteId}',
    (first.payload #>> '{nextCursor,pending}')::boolean,
    10
  )
from late_acceptance_inbox_results as first
where first.page_number = 1;

select is(
  (select pg_catalog.jsonb_array_length(payload->'incoming')
    from late_acceptance_inbox_results where page_number = 2),
  2,
  'late accepted invitations remain pageable beyond the old 31-day cursor window'
);
select is(
  (select payload->'nextCursor'
    from late_acceptance_inbox_results where page_number = 2),
  'null'::jsonb,
  'late accepted invitation history terminates with a bounded cursor'
);

set local request.jwt.claim.sub = 'f1000000-0000-4000-8000-000000000004';
set local request.jwt.claims =
  '{"sub":"f1000000-0000-4000-8000-000000000004","role":"authenticated","session_id":"f2000000-0000-4000-8000-000000000004"}';
select throws_ok(
  $$select public.social_workout_invite_plan(
    'wi_00000000000000000000000000000001', 1
  )$$,
  'P0002',
  'Social resource unavailable.',
  'another account cannot read or distinguish the invite'
);
select is(
  pg_catalog.jsonb_array_length(
    public.social_workout_inbox_page(null, null, null, 10)->'incoming'
  ),
  0,
  'another account cannot page late accepted invitations'
);

set local request.jwt.claim.sub = 'f1000000-0000-4000-8000-000000000003';
set local request.jwt.claims =
  '{"sub":"f1000000-0000-4000-8000-000000000003","role":"authenticated","session_id":"f2000000-0000-4000-8000-000000000003"}';

delete from gymapp_private.social_workout_invites
where sender_user_id in (
    'f1000000-0000-4000-8000-000000000001',
    'f1000000-0000-4000-8000-000000000002',
    'f1000000-0000-4000-8000-000000000003',
    'f1000000-0000-4000-8000-000000000004'
  )
  or recipient_user_id in (
    'f1000000-0000-4000-8000-000000000001',
    'f1000000-0000-4000-8000-000000000002',
    'f1000000-0000-4000-8000-000000000003',
    'f1000000-0000-4000-8000-000000000004'
  );

insert into gymapp_private.friendships (
  id, user_low_id, user_high_id, requester_user_id, status,
  revision, requested_at, responded_at, updated_at
) values (
  'f_10000000000000000000000000000003',
  'f1000000-0000-4000-8000-000000000003',
  'f1000000-0000-4000-8000-000000000004',
  'f1000000-0000-4000-8000-000000000003',
  'accepted', 2,
  pg_catalog.clock_timestamp() - interval '2 days',
  pg_catalog.clock_timestamp() - interval '1 day',
  pg_catalog.clock_timestamp() - interval '1 day'
);

create temporary table maximum_social_workout_payload
on commit drop
as
with names as (
  select
    series.number,
    pg_catalog.repeat('😀', 119) || pg_catalog.chr(64 + series.number) as name
  from pg_catalog.generate_series(1, 20) as series(number)
)
select
  pg_catalog.jsonb_build_object(
    'version', 1,
    'exercises', pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'name', names.name,
        'sets', pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object('weight', 1, 'reps', 1)
        )
      ) order by names.number
    )
  ) as workout,
  pg_catalog.jsonb_build_object(
    'exerciseCount', 20,
    'setCount', 20,
    'exerciseNames', pg_catalog.jsonb_agg(
      pg_catalog.to_jsonb(names.name) order by names.number
    )
  ) as summary
from names;

create temporary table maximum_escaped_social_workout_payload
on commit drop
as
with names as (
  select
    series.number,
    pg_catalog.repeat(E'\\', 119) || pg_catalog.chr(64 + series.number) as name
  from pg_catalog.generate_series(1, 20) as series(number)
)
select
  pg_catalog.jsonb_build_object(
    'version', 1,
    'exercises', pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'name', names.name,
        'sets', pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object('weight', 1, 'reps', 1)
        )
      ) order by names.number
    )
  ) as workout,
  pg_catalog.jsonb_build_object(
    'exerciseCount', 20,
    'setCount', 20,
    'exerciseNames', pg_catalog.jsonb_agg(
      pg_catalog.to_jsonb(names.name) order by names.number
    )
  ) as summary
from names;

select ok(
  (
    select pg_catalog.pg_column_size(summary) <= 16384
      and pg_catalog.octet_length(
        pg_catalog.convert_to(summary::text, 'UTF8')
      ) > 9000
      and pg_catalog.jsonb_array_length(summary->'exerciseNames') = 20
    from maximum_social_workout_payload
  ),
  'worst-case valid summary stays within the 16 KiB JSONB and client field bounds'
);
select ok(
  (
    select gymapp_private.validate_social_workout(workout) = workout
      and gymapp_private.social_workout_summary(workout) = summary
      and pg_catalog.octet_length(
        pg_catalog.convert_to(summary::text, 'UTF8')
      ) > 4500
    from maximum_escaped_social_workout_payload
  ),
  'worst escaped structurally valid summary passes canonical server validation'
);

with fixture as (
  select
    series.number,
    pg_catalog.clock_timestamp()
      - pg_catalog.make_interval(secs => series.number::double precision) as created_at
  from pg_catalog.generate_series(1, 25) as series(number)
)
insert into gymapp_private.social_workout_invites (
  id, sender_user_id, recipient_user_id, client_request_id, status,
  workout, summary, revision, created_at, expires_at, responded_at, updated_at
)
select
  'wi_' || pg_catalog.lpad(pg_catalog.to_hex(1000 + fixture.number), 32, '0'),
  'f1000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000003',
  pg_catalog.gen_random_uuid(),
  'pending',
  case when fixture.number = 1 then escaped.workout else payload.workout end,
  case when fixture.number = 1 then escaped.summary else payload.summary end,
  1,
  fixture.created_at,
  fixture.created_at + interval '7 days',
  null,
  fixture.created_at
from fixture
cross join maximum_social_workout_payload as payload
cross join maximum_escaped_social_workout_payload as escaped;

with fixture as (
  select
    series.number,
    pg_catalog.clock_timestamp()
      - pg_catalog.make_interval(secs => series.number::double precision) as created_at
  from pg_catalog.generate_series(1, 20) as series(number)
)
insert into gymapp_private.social_workout_invites (
  id, sender_user_id, recipient_user_id, client_request_id, status,
  workout, summary, revision, created_at, expires_at, responded_at, updated_at
)
select
  'wi_' || pg_catalog.lpad(pg_catalog.to_hex(2000 + fixture.number), 32, '0'),
  'f1000000-0000-4000-8000-000000000003',
  'f1000000-0000-4000-8000-000000000004',
  pg_catalog.gen_random_uuid(),
  'accepted',
  payload.workout,
  payload.summary,
  2,
  fixture.created_at,
  fixture.created_at + interval '7 days',
  fixture.created_at + interval '1 second',
  fixture.created_at + interval '1 second'
from fixture
cross join maximum_social_workout_payload as payload;

select ok(
  pg_catalog.octet_length(pg_catalog.convert_to(
    pg_catalog.jsonb_build_object(
      'version', 2,
      'pendingIncomingCount', 25,
      'incoming', (
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'inviteId', invite.id,
          'profileId', profile.public_id,
          'displayName', gymapp_private.social_safe_display_name(profile.display_name),
          'status', invite.status,
          'inviteRevision', invite.revision,
          'createdAt', invite.created_at,
          'expiresAt', invite.expires_at,
          'respondedAt', invite.responded_at,
          'summary', invite.summary
        ) order by invite.created_at desc, invite.id desc)
        from (
          select candidate.*
          from gymapp_private.social_workout_invites as candidate
          where candidate.recipient_user_id = 'f1000000-0000-4000-8000-000000000003'
          order by candidate.created_at desc, candidate.id desc
          limit 10
        ) as invite
        join public.profiles as profile on profile.user_id = invite.sender_user_id
      ),
      'outgoing', (
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'inviteId', invite.id,
          'profileId', profile.public_id,
          'displayName', gymapp_private.social_safe_display_name(profile.display_name),
          'status', invite.status,
          'inviteRevision', invite.revision,
          'createdAt', invite.created_at,
          'expiresAt', invite.expires_at,
          'respondedAt', invite.responded_at,
          'summary', invite.summary
        ) order by invite.created_at desc, invite.id desc)
        from (
          select candidate.*
          from gymapp_private.social_workout_invites as candidate
          where candidate.sender_user_id = 'f1000000-0000-4000-8000-000000000003'
          order by candidate.created_at desc, candidate.id desc
          limit 20
        ) as invite
        join public.profiles as profile on profile.user_id = invite.recipient_user_id
      ),
      'nextCursor', 'null'::jsonb
    )::text,
    'UTF8'
  )) > 262144,
  'worst-case valid summaries reproduce the former aggregate overflow'
);

create temporary table large_inbox_results (
  page_number integer primary key,
  payload jsonb not null
) on commit drop;

insert into large_inbox_results (page_number, payload)
values (1, public.social_workout_inbox_page(null, null, null, 10));

insert into large_inbox_results (page_number, payload)
select
  2,
  public.social_workout_inbox_page(
    (first.payload #>> '{nextCursor,createdAt}')::timestamptz,
    first.payload #>> '{nextCursor,inviteId}',
    (first.payload #>> '{nextCursor,pending}')::boolean,
    10
  )
from large_inbox_results as first
where first.page_number = 1;

select ok(
  not exists (
    select 1
    from large_inbox_results
    where pg_catalog.octet_length(
      pg_catalog.convert_to(payload::text, 'UTF8')
    ) > 258048
  ),
  'large-summary response stays inside the shared client byte limit'
);
select ok(
  (
    select pg_catalog.jsonb_array_length(payload->'incoming') >= 1
      and pg_catalog.jsonb_array_length(payload->'outgoing') >= 1
      and payload #>> '{incoming,0,summary,exerciseNames,0}' =
        pg_catalog.repeat(E'\\', 119) || 'A'
    from large_inbox_results
    where page_number = 1
  ),
  'worst escaped valid single incoming row survives beside the maximum outgoing prefix'
);
select ok(
  not exists (
    select 1
    from large_inbox_results
    where pg_catalog.jsonb_array_length(payload->'incoming') <> 10
  ),
  'two ten-row client pages remain available for worst-case valid summaries'
);
select ok(
  not exists (
    select first_invite.value->>'inviteId'
    from large_inbox_results as first_result,
      lateral pg_catalog.jsonb_array_elements(first_result.payload->'incoming') as first_invite(value)
    join large_inbox_results as second_result on second_result.page_number = 2
    cross join lateral pg_catalog.jsonb_array_elements(second_result.payload->'incoming') as second_invite(value)
    where first_result.page_number = 1
      and first_invite.value->>'inviteId' = second_invite.value->>'inviteId'
  ),
  'large-summary cursor pages do not repeat an incoming row'
);
select ok(
  (
    select pg_catalog.jsonb_array_length(payload->'outgoing') between 1 and 19
    from large_inbox_results
    where page_number = 1
  ),
  'outgoing byte budget keeps only a newest-first prefix'
);
select ok(
  (
    select pg_catalog.octet_length(
      pg_catalog.convert_to((payload->'outgoing')::text, 'UTF8')
    ) <= 98304
    from large_inbox_results
    where page_number = 1
  ),
  'outgoing snapshot respects its exact UTF-8 byte budget'
);
select is(
  (
    select pg_catalog.string_agg(item.value->>'inviteId', ',' order by item.ordinality)
    from large_inbox_results as result,
      lateral pg_catalog.jsonb_array_elements(result.payload->'outgoing')
        with ordinality as item(value, ordinality)
    where result.page_number = 1
  ),
  (
    select pg_catalog.string_agg(expected.id, ',' order by expected.created_at desc, expected.id desc)
    from (
      select invite.id, invite.created_at
      from gymapp_private.social_workout_invites as invite
      where invite.sender_user_id = 'f1000000-0000-4000-8000-000000000003'
      order by invite.created_at desc, invite.id desc
      limit (
        select pg_catalog.jsonb_array_length(payload->'outgoing')
        from large_inbox_results
        where page_number = 1
      )
    ) as expected
  ),
  'outgoing byte budget preserves the exact newest rows'
);
select is(
  (select payload->'outgoing' from large_inbox_results where page_number = 1),
  (select payload->'outgoing' from large_inbox_results where page_number = 2),
  'outgoing snapshot is stable across incoming pages'
);

create temporary table wide_inbox_result (
  payload jsonb not null
) on commit drop;
insert into wide_inbox_result (payload)
values (public.social_workout_inbox_page(null, null, null, 20));

select ok(
  (
    select pg_catalog.jsonb_array_length(payload->'incoming') between 1 and 19
      and payload->'nextCursor' <> 'null'::jsonb
    from wide_inbox_result
  ),
  'exact response budget returns a nonempty short page when twenty rows do not fit'
);
select ok(
  (
    select
      payload #>> '{nextCursor,inviteId}' =
        payload->'incoming'->(pg_catalog.jsonb_array_length(payload->'incoming') - 1)->>'inviteId'
      and payload #>> '{nextCursor,createdAt}' =
        payload->'incoming'->(pg_catalog.jsonb_array_length(payload->'incoming') - 1)->>'createdAt'
      and (payload #>> '{nextCursor,pending}')::boolean =
        ((payload->'incoming'->(pg_catalog.jsonb_array_length(payload->'incoming') - 1)->>'status') = 'pending')
    from wide_inbox_result
  ),
  'byte-budgeted incoming cursor identifies the exact last emitted row'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.social_workout_inbox_page(timestamptz,text,boolean,integer)',
    'EXECUTE'
  ) and pg_catalog.has_function_privilege(
    'authenticated',
    'public.social_workout_inbox_page(timestamptz,text,boolean,integer)',
    'EXECUTE'
  ),
  'anonymous clients cannot execute the metadata inbox'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.social_workout_invite_plan(text,bigint)',
    'EXECUTE'
  ) and pg_catalog.has_function_privilege(
    'authenticated',
    'public.social_workout_invite_plan(text,bigint)',
    'EXECUTE'
  ),
  'detail execution is granted only to authenticated clients'
);

select * from finish();

rollback;
