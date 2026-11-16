-- Apple Ads attribution: public.record_ad_attribution(...) and the private
-- gymapp_private.ad_attributions / apple_ads_funnel objects.
--
-- Covers the owner happy path, first-write-wins idempotence, denied callers
-- (anon, expired/foreign session, direct table and view access), malformed
-- input (shape, ranges, enums, install timestamp), absence of side effects on
-- rejection, the funnel view, and cascade on auth user deletion. All fixtures
-- are synthetic and rolled back.
begin;

select plan(32);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '00000000-0000-0000-0000-000000000000',
    'ad900000-0000-4000-8000-000000000001',
    'authenticated', 'authenticated', 'ads-a@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'ad900000-0000-4000-8000-000000000002',
    'authenticated', 'authenticated', 'ads-b@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'ad900000-0000-4000-8000-000000000003',
    'authenticated', 'authenticated', 'ads-c@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'ad900000-0000-4000-8000-000000000004',
    'authenticated', 'authenticated', 'ads-d@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

-- A, B and D hold live sessions; C holds an expired one.
insert into auth.sessions (id, user_id, not_after, created_at, updated_at) values
  (
    'ad910000-0000-4000-8000-000000000001',
    'ad900000-0000-4000-8000-000000000001',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'ad910000-0000-4000-8000-000000000002',
    'ad900000-0000-4000-8000-000000000002',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'ad910000-0000-4000-8000-000000000003',
    'ad900000-0000-4000-8000-000000000003',
    pg_catalog.clock_timestamp() - interval '1 second',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'ad910000-0000-4000-8000-000000000004',
    'ad900000-0000-4000-8000-000000000004',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

-- Builds the JWT claims PostgREST would hand the database: sub, role, session.
create function pg_temp.act_as(p_user uuid, p_session uuid)
returns void
language sql
as $$
  select pg_catalog.set_config(
    'request.jwt.claim.sub', coalesce(p_user::text, ''), true
  ), pg_catalog.set_config(
    'request.jwt.claims',
    pg_catalog.jsonb_build_object(
      'sub', p_user,
      'role', 'authenticated',
      'session_id', p_session
    )::text,
    true
  )
$$;

grant execute on function pg_temp.act_as(uuid, uuid) to authenticated, anon;

-- ---------------------------------------------------------------------------
-- Static boundary: grants, signature, privileges on the private objects.
-- ---------------------------------------------------------------------------
select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.record_ad_attribution(boolean,bigint,bigint,bigint,bigint,text,text,text,text,timestamptz)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.record_ad_attribution(boolean,bigint,bigint,bigint,bigint,text,text,text,text,timestamptz)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'public.record_ad_attribution(boolean,bigint,bigint,bigint,bigint,text,text,text,text,timestamptz)',
    'EXECUTE'
  ),
  'record_ad_attribution is executable by authenticated only, not anon or service_role'
);

select is_empty(
  $q$
    select arg.arg_name
    from pg_catalog.pg_proc as p
    cross join lateral pg_catalog.unnest(p.proargnames) as arg(arg_name)
    where p.oid = 'public.record_ad_attribution(boolean,bigint,bigint,bigint,bigint,text,text,text,text,timestamptz)'::pg_catalog.regprocedure
      and arg.arg_name ~* '(user|owner|uid)'
  $q$,
  'record_ad_attribution takes no user identifier parameter'
);

select ok(
  (select class_row.relrowsecurity and class_row.relforcerowsecurity
   from pg_catalog.pg_class as class_row
   where class_row.oid = 'gymapp_private.ad_attributions'::pg_catalog.regclass),
  'ad_attributions has row level security enabled and forced'
);

-- ---------------------------------------------------------------------------
-- anon is denied.
-- ---------------------------------------------------------------------------
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
select throws_ok(
  $q$
    select public.record_ad_attribution(
      false, null, null, null, null, null, null, null, null,
      pg_catalog.clock_timestamp()
    )
  $q$,
  '42501',
  null,
  'anon cannot execute record_ad_attribution'
);
select throws_ok(
  $q$ select * from gymapp_private.apple_ads_funnel $q$,
  '42501',
  null,
  'anon cannot read the funnel view'
);
reset role;

-- ---------------------------------------------------------------------------
-- authenticated has no direct access to the table or the view.
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as(
  'ad900000-0000-4000-8000-000000000001',
  'ad910000-0000-4000-8000-000000000001'
);
select throws_ok(
  $q$ select * from gymapp_private.ad_attributions $q$,
  '42501', null,
  'authenticated cannot select ad_attributions'
);
select throws_ok(
  $q$
    insert into gymapp_private.ad_attributions (user_id, attributed, install_seen_at)
    values ('ad900000-0000-4000-8000-000000000001', false, pg_catalog.clock_timestamp())
  $q$,
  '42501', null,
  'authenticated cannot insert into ad_attributions directly'
);
select throws_ok(
  $q$ update gymapp_private.ad_attributions set attributed = true $q$,
  '42501', null,
  'authenticated cannot update ad_attributions'
);
select throws_ok(
  $q$ delete from gymapp_private.ad_attributions $q$,
  '42501', null,
  'authenticated cannot delete from ad_attributions'
);
select throws_ok(
  $q$ select * from gymapp_private.apple_ads_funnel $q$,
  '42501', null,
  'authenticated cannot read the funnel view'
);

-- ---------------------------------------------------------------------------
-- Owner happy path and first-write-wins idempotence (A, attributed).
-- ---------------------------------------------------------------------------
select is(
  public.record_ad_attribution(
    true, 111, 222, 333, 444, 'Download', 'Click', 'US',
    'APPSTORE_SEARCH_RESULTS', pg_catalog.clock_timestamp() - interval '1 day'
  ),
  true,
  'the owner inserts a first attribution and gets true'
);

reset role;
select results_eq(
  $q$
    select attributed, campaign_id, ad_group_id, keyword_id, ad_id,
           conversion_type, claim_type, country_or_region, supply_placement, source
    from gymapp_private.ad_attributions
    where user_id = 'ad900000-0000-4000-8000-000000000001'
  $q$,
  $q$
    values (true, 111::bigint, 222::bigint, 333::bigint, 444::bigint,
            'Download', 'Click', 'US', 'APPSTORE_SEARCH_RESULTS', 'apple_ads')
  $q$,
  'the stored row holds the parsed fields for the caller'
);

set local role authenticated;
select pg_temp.act_as(
  'ad900000-0000-4000-8000-000000000001',
  'ad910000-0000-4000-8000-000000000001'
);
select is(
  public.record_ad_attribution(
    false, null, null, null, null, null, null, null, null,
    pg_catalog.clock_timestamp()
  ),
  false,
  'a second call for the same account returns false'
);
reset role;
select results_eq(
  $q$
    select attributed, campaign_id, ad_group_id
    from gymapp_private.ad_attributions
    where user_id = 'ad900000-0000-4000-8000-000000000001'
  $q$,
  $q$ values (true, 111::bigint, 222::bigint) $q$,
  'the second call leaves the first attribution unchanged'
);

-- ---------------------------------------------------------------------------
-- Organic baseline (B, attributed = false).
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as(
  'ad900000-0000-4000-8000-000000000002',
  'ad910000-0000-4000-8000-000000000002'
);
select is(
  public.record_ad_attribution(
    false, null, null, null, null, null, null, null, null,
    pg_catalog.clock_timestamp() - interval '2 hours'
  ),
  true,
  'an unattributed (organic) result is stored and returns true'
);
reset role;
select results_eq(
  $q$
    select attributed, campaign_id is null and ad_group_id is null
    from gymapp_private.ad_attributions
    where user_id = 'ad900000-0000-4000-8000-000000000002'
  $q$,
  $q$ values (false, true) $q$,
  'the organic row carries no campaign data'
);

-- ---------------------------------------------------------------------------
-- Denied sessions: expired session (C) and a foreign session (A with B's).
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as(
  'ad900000-0000-4000-8000-000000000003',
  'ad910000-0000-4000-8000-000000000003'
);
select throws_ok(
  $q$
    select public.record_ad_attribution(
      false, null, null, null, null, null, null, null, null,
      pg_catalog.clock_timestamp()
    )
  $q$,
  '42501',
  'A live authenticated session is required.',
  'an expired session is rejected'
);
select pg_temp.act_as(
  'ad900000-0000-4000-8000-000000000004',
  'ad910000-0000-4000-8000-000000000002'
);
select throws_ok(
  $q$
    select public.record_ad_attribution(
      false, null, null, null, null, null, null, null, null,
      pg_catalog.clock_timestamp()
    )
  $q$,
  '42501',
  'A live authenticated session is required.',
  'another account''s session id is rejected'
);

-- ---------------------------------------------------------------------------
-- Malformed input (D holds a live session and has no row yet).
-- ---------------------------------------------------------------------------
select pg_temp.act_as(
  'ad900000-0000-4000-8000-000000000004',
  'ad910000-0000-4000-8000-000000000004'
);
select throws_ok(
  $q$
    select public.record_ad_attribution(
      true, null, 222, null, null, null, null, null, null,
      pg_catalog.clock_timestamp()
    )
  $q$,
  '23514', null,
  'attributed without a campaign violates the shape check'
);
select throws_ok(
  $q$
    select public.record_ad_attribution(
      false, 111, null, null, null, null, null, null, null,
      pg_catalog.clock_timestamp()
    )
  $q$,
  '23514', null,
  'unattributed with campaign data violates the shape check'
);
select throws_ok(
  $q$
    select public.record_ad_attribution(
      true, 0, 222, null, null, null, null, null, null,
      pg_catalog.clock_timestamp()
    )
  $q$,
  '23514', null,
  'a non-positive campaign id is rejected'
);
select throws_ok(
  $q$
    select public.record_ad_attribution(
      true, 111, 222, null, null, 'Install', null, null, null,
      pg_catalog.clock_timestamp()
    )
  $q$,
  '23514', null,
  'an unknown conversion type is rejected'
);
select throws_ok(
  $q$
    select public.record_ad_attribution(
      true, 111, 222, null, null, null, null, 'us', null,
      pg_catalog.clock_timestamp()
    )
  $q$,
  '23514', null,
  'a malformed country code is rejected'
);
select throws_ok(
  $q$
    select public.record_ad_attribution(
      false, null, null, null, null, null, null, null, null,
      pg_catalog.clock_timestamp() - interval '401 days'
    )
  $q$,
  '22023', 'Invalid attribution.',
  'an install time older than 400 days is rejected'
);
select throws_ok(
  $q$
    select public.record_ad_attribution(
      false, null, null, null, null, null, null, null, null,
      pg_catalog.clock_timestamp() + interval '1 hour'
    )
  $q$,
  '22023', 'Invalid attribution.',
  'an install time in the future is rejected'
);
select throws_ok(
  $q$
    select public.record_ad_attribution(
      false, null, null, null, null, null, null, null, null, null
    )
  $q$,
  '22023', 'Invalid attribution.',
  'a null install time is rejected'
);

reset role;
select is(
  (select pg_catalog.count(*)
   from gymapp_private.ad_attributions
   where user_id in (
     'ad900000-0000-4000-8000-000000000003',
     'ad900000-0000-4000-8000-000000000004'
   )),
  0::bigint,
  'rejected calls store no row'
);

-- ---------------------------------------------------------------------------
-- Funnel view (read as the owner role; organic rows repeat across grouping sets): A is campaign 111 / ad group 222.
-- ---------------------------------------------------------------------------
select results_eq(
  $q$
    select signed_in_users, new_signups, new_signups_with_workout, users_with_workout
    from gymapp_private.apple_ads_funnel
    where attributed and campaign_id = 111 and ad_group_id is null
  $q$,
  $q$ values (1::bigint, 1::bigint, 0::bigint, 0::bigint) $q$,
  'the funnel counts the attributed account at campaign level'
);
select results_eq(
  $q$
    select distinct signed_in_users
    from gymapp_private.apple_ads_funnel
    where not attributed and campaign_id is null
  $q$,
  $q$ values (1::bigint) $q$,
  'the funnel counts the organic account in the baseline row'
);

-- ---------------------------------------------------------------------------
-- Cascade: deleting the auth user removes only its own attribution.
-- ---------------------------------------------------------------------------
select is(
  (select pg_catalog.count(*) from gymapp_private.ad_attributions
   where user_id in (
     'ad900000-0000-4000-8000-000000000001',
     'ad900000-0000-4000-8000-000000000002'
   )),
  2::bigint,
  'A and B each hold one attribution before deletion'
);
delete from auth.users where id = 'ad900000-0000-4000-8000-000000000001';
select is(
  (select pg_catalog.count(*) from gymapp_private.ad_attributions
   where user_id = 'ad900000-0000-4000-8000-000000000001'),
  0::bigint,
  'deleting the auth user cascades its attribution'
);
select is(
  (select pg_catalog.count(*) from gymapp_private.ad_attributions
   where user_id = 'ad900000-0000-4000-8000-000000000002'),
  1::bigint,
  'deleting A leaves B''s attribution in place'
);

select * from finish();

rollback;
