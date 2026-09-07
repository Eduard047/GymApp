begin;

select plan(30);

select has_table(
  'gymapp_private',
  'garmin_gateway_preauth_buckets',
  'fixed Garmin gateway ingress table exists'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.garmin_gateway_preauth_buckets),
  192::bigint,
  'Garmin gateway ingress state has exactly 192 rows'
);
select is(
  (select pg_catalog.count(distinct bucket.bucket_lane)
   from gymapp_private.garmin_gateway_preauth_buckets as bucket),
  3::bigint,
  'Garmin gateway ingress has global, JWT, and capability lanes only'
);
select ok(
  not exists (
    select 1
    from gymapp_private.garmin_gateway_preauth_buckets as bucket
    group by bucket.bucket_lane
    having pg_catalog.count(*) <> 64
  ),
  'every Garmin gateway lane has exactly 64 pre-seeded shards'
);
select ok(
  not pg_catalog.has_table_privilege(
    'authenticated',
    'gymapp_private.garmin_gateway_preauth_buckets',
    'SELECT'
  ),
  'authenticated clients cannot inspect Garmin ingress state'
);
select ok(
  (
    select relation.relforcerowsecurity
    from pg_catalog.pg_class as relation
    where relation.oid =
      'gymapp_private.garmin_gateway_preauth_buckets'::regclass
  ),
  'Garmin ingress state forces RLS for every non-bypass owner'
);
select has_function(
  'public',
  'garmin_gateway_preauth_debit',
  array['text', 'integer'],
  'service Garmin ingress debit exists'
);
select ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'public.garmin_gateway_preauth_debit(text,integer)',
    'EXECUTE'
  ),
  'service role can debit Garmin ingress state'
);
select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.garmin_gateway_preauth_debit(text,integer)',
    'EXECUTE'
  ),
  'anonymous clients cannot debit Garmin ingress state directly'
);
select ok(
  pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef(
        'gymapp_private.consume_garmin_gateway_preauth_budget(text,integer)'::regprocedure
      )
    ),
    'insert into'
  ) = 0,
  'Garmin debit cannot create attacker-selected rows'
);

update gymapp_private.garmin_gateway_preauth_buckets as bucket
set tokens = 0,
    refilled_at = pg_catalog.clock_timestamp() + interval '1 minute'
where bucket.shard_id = 63
  and bucket.bucket_lane in ('global', 'jwt');
select is(
  gymapp_private.consume_garmin_gateway_preauth_budget('jwt', 63) ->> 'allowed',
  'false',
  'exhausted fixed Garmin lanes fail closed'
);

select has_function(
  'public',
  'social_my_friend_code',
  array[]::text[],
  'public friend-code v1 signature remains available'
);
select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.social_my_friend_code()',
    'EXECUTE'
  ),
  'authenticated clients retain friend-code access'
);
select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'gymapp_private.social_my_friend_code_storage_v1()',
    'EXECUTE'
  ),
  'friend-code storage worker is private'
);
select ok(
  pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef(
        'gymapp_private.social_my_friend_code_direct_worker()'::regprocedure
      )
    ),
    'social_begin_direct_request'
  ) > 0
  and pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef(
        'gymapp_private.social_my_friend_code_direct_worker()'::regprocedure
      )
    ),
    'social_require_caller'
  ) > 0
  and pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef(
        'gymapp_private.social_my_friend_code_direct_worker()'::regprocedure
      )
    ),
    'social_commit_direct_rejection'
  ) > 0,
  'friend-code worker durably meters success and reviewed rejections'
);

select has_table(
  'gymapp_private',
  'account_deletion_operations',
  'private account-deletion operation journal exists'
);
select col_type_is(
  'gymapp_private',
  'account_deletion_operations',
  'operation_id',
  'uuid',
  'account-deletion operation ID is a UUID'
);
select ok(
  not pg_catalog.has_table_privilege(
    'authenticated',
    'gymapp_private.account_deletion_operations',
    'SELECT'
  ),
  'clients cannot inspect committed deletion operations'
);
select ok(
  (
    select relation.relforcerowsecurity
    from pg_catalog.pg_class as relation
    where relation.oid =
      'gymapp_private.account_deletion_operations'::regclass
  ),
  'account-deletion operation journal forces RLS'
);
select has_function(
  'public',
  'consume_account_deletion_grant',
  array['text'],
  'legacy deletion consume RPC retains its public signature'
);
select ok(
  pg_catalog.pg_get_function_result(
    'public.consume_account_deletion_grant(text)'::regprocedure
  ) = 'uuid',
  'legacy deletion consume RPC retains its UUID response'
);
select has_function(
  'public',
  'commit_account_deletion_operation',
  array['text'],
  'versioned deletion commit RPC is available'
);
select ok(
  pg_catalog.pg_get_function_result(
    'public.commit_account_deletion_operation(text)'::regprocedure
  ) = 'jsonb',
  'new deletion commit RPC returns a versioned JSON proof'
);
select ok(
  pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef(
        'gymapp_private.commit_account_deletion_operation(text)'::regprocedure
      )
    ),
    'from gymapp_private.account_deletion_operations'
  ) < pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef(
        'gymapp_private.commit_account_deletion_operation(text)'::regprocedure
      )
    ),
    'for share'
  )
  and pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef(
        'gymapp_private.commit_account_deletion_operation(text)'::regprocedure
      )
    ),
    'for share'
  ) < pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef(
        'gymapp_private.commit_account_deletion_operation(text)'::regprocedure
      )
    ),
    'insert into gymapp_private.account_deletion_operations'
  ),
  'deletion replay precedes live-session serialization and first commit follows it'
);

select col_type_is(
  'gymapp_private',
  'push_outbox_deliveries',
  'send_authorized_at',
  'timestamp with time zone',
  'push send authorization records its commit time'
);
select col_type_is(
  'gymapp_private',
  'push_outbox_deliveries',
  'send_authorized_lease_token',
  'uuid',
  'push send authorization is bound to a UUID lease'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger as trigger
    where trigger.tgrelid =
      'gymapp_private.push_outbox_deliveries'::regclass
      and trigger.tgname =
        'push_outbox_deliveries_send_authorization_guard'
      and not trigger.tgisinternal
  ),
  'every push lease/status transition is guarded'
);
select has_function(
  'public',
  'push_authorize_delivery_send',
  array['uuid', 'uuid'],
  'atomic push send-authorization RPC exists'
);
select ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'public.push_authorize_delivery_send(uuid,uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'public.push_authorize_delivery_send(uuid,uuid)',
    'EXECUTE'
  ),
  'only service role can authorize provider sends'
);
select ok(
  pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef(
        'gymapp_private.authorize_push_delivery_send(uuid,uuid)'::regprocedure
      )
    ),
    'for share'
  ) < pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef(
        'gymapp_private.authorize_push_delivery_send(uuid,uuid)'::regprocedure
      )
    ),
    'send_authorized_at'
  )
  and pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef(
        'public.push_delivery_is_current(uuid,uuid)'::regprocedure
      )
    ),
    'authorize_push_delivery_send'
  ) > 0,
  'push revocation lock precedes authorization and the old RPC is a safe alias'
);

select * from finish();

rollback;
