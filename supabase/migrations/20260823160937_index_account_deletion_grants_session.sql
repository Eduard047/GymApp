begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

create index account_deletion_grants_session_idx
  on gymapp_private.account_deletion_grants (session_id);

commit;
