begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
begin
  if pg_catalog.to_regprocedure('gymapp_private.current_auth_session_is_live()') is null
     or pg_catalog.to_regclass('gymapp_private.user_state_progression') is null then
    raise exception 'GymApp Apple Ads attribution prerequisites are missing.';
  end if;
end
$preflight$;

-- One Apple Ads (AdServices) attribution result per account, uploaded once by
-- the iPhone client for the first cloud account that signs in or up. No IDFA,
-- no click/impression dates, no token. Cascades away with the auth user.
create table gymapp_private.ad_attributions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  source text not null default 'apple_ads' check (source = 'apple_ads'),
  attributed boolean not null,
  campaign_id bigint check (campaign_id > 0),
  ad_group_id bigint check (ad_group_id > 0),
  keyword_id bigint check (keyword_id > 0),
  ad_id bigint check (ad_id > 0),
  conversion_type text check (conversion_type in ('Download', 'Redownload', 'PreOrder')),
  claim_type text check (claim_type in ('Click', 'Impression')),
  country_or_region text check (country_or_region ~ '^[A-Z]{2}$'),
  supply_placement text check (supply_placement in (
    'APPSTORE_SEARCH_RESULTS', 'APPSTORE_SEARCH_TAB',
    'APPSTORE_TODAY_TAB', 'APPSTORE_PRODUCT_PAGES')),
  install_seen_at timestamptz not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint ad_attr_shape check (
    (attributed and campaign_id is not null and ad_group_id is not null)
    or (not attributed and campaign_id is null and ad_group_id is null
        and keyword_id is null and ad_id is null and conversion_type is null
        and claim_type is null and country_or_region is null
        and supply_placement is null))
);

alter table gymapp_private.ad_attributions enable row level security;
alter table gymapp_private.ad_attributions force row level security;
revoke all on table gymapp_private.ad_attributions
  from public, anon, authenticated, service_role;

create index ad_attributions_campaign_idx
  on gymapp_private.ad_attributions (campaign_id)
  where attributed;

create or replace function public.record_ad_attribution(
  p_attributed boolean,
  p_campaign_id bigint,
  p_ad_group_id bigint,
  p_keyword_id bigint,
  p_ad_id bigint,
  p_conversion_type text,
  p_claim_type text,
  p_country_or_region text,
  p_supply_placement text,
  p_install_seen_at timestamptz
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
set statement_timeout = '5s'
set lock_timeout = '2s'
as $function$
declare
  caller uuid := auth.uid();
  inserted integer;
begin
  if caller is null or not gymapp_private.current_auth_session_is_live() then
    raise exception using errcode = '42501',
      message = 'A live authenticated session is required.';
  end if;

  if p_attributed is null
     or p_install_seen_at is null
     or p_install_seen_at < pg_catalog.clock_timestamp() - interval '400 days'
     or p_install_seen_at > pg_catalog.clock_timestamp() + interval '5 minutes' then
    raise exception using errcode = '22023', message = 'Invalid attribution.';
  end if;

  insert into gymapp_private.ad_attributions (
    user_id, attributed, campaign_id, ad_group_id, keyword_id, ad_id,
    conversion_type, claim_type, country_or_region, supply_placement,
    install_seen_at
  ) values (
    caller, p_attributed, p_campaign_id, p_ad_group_id, p_keyword_id, p_ad_id,
    p_conversion_type, p_claim_type, p_country_or_region, p_supply_placement,
    p_install_seen_at
  ) on conflict (user_id) do nothing;

  get diagnostics inserted = row_count;
  return inserted = 1;
end
$function$;

revoke all on function public.record_ad_attribution(
  boolean, bigint, bigint, bigint, bigint, text, text, text, text, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.record_ad_attribution(
  boolean, bigint, bigint, bigint, bigint, text, text, text, text, timestamptz
) to authenticated;

-- Operator-only funnel (read with the owner role; no client grant).
create view gymapp_private.apple_ads_funnel with (security_invoker = true) as
select
  a.attributed,
  a.campaign_id,
  a.ad_group_id,
  a.keyword_id,
  count(*) as signed_in_users,
  count(*) filter (
    where u.created_at >= a.install_seen_at - interval '10 minutes'
  ) as new_signups,
  count(*) filter (
    where u.created_at >= a.install_seen_at - interval '10 minutes'
      and coalesce(p.workouts, 0) >= 1
  ) as new_signups_with_workout,
  count(*) filter (where coalesce(p.workouts, 0) >= 1) as users_with_workout
from gymapp_private.ad_attributions as a
join auth.users as u on u.id = a.user_id
left join gymapp_private.user_state_progression as p on p.user_id = a.user_id
group by grouping sets (
  (a.attributed),
  (a.attributed, a.campaign_id),
  (a.attributed, a.campaign_id, a.ad_group_id, a.keyword_id)
);

revoke all on table gymapp_private.apple_ads_funnel
  from public, anon, authenticated, service_role;

notify pgrst, 'reload schema';

commit;
