-- Wallet writes are available exclusively to authenticated Edge handlers.
create table private.diamond_wallets (
  member_id uuid primary key references auth.users on delete cascade,
  balance bigint not null default 0 check (balance between 0 and 9007199254740991),
  migrated boolean not null default false,
  imported_digest bytea
);

create table private.diamond_intents (
  id uuid primary key,
  member_id uuid not null references auth.users on delete cascade,
  source text not null check (source in ('districtWallet', 'communityOrder')),
  product text not null check (product ~ '^[A-Za-z0-9._-]{1,100}$'),
  quantity integer not null check (quantity = 1),
  installation uuid not null,
  edition text not null,
  order_ref text,
  created_at timestamptz not null default now(),
  check (source = 'communityOrder' or order_ref is null)
);
create index diamond_intents_member on private.diamond_intents(member_id);
-- Reserve a referenced upstream order before presenting an Apple payment sheet.
create unique index diamond_intents_external_ref on private.diamond_intents(order_ref)
  where source = 'communityOrder' and order_ref is not null;

-- Candidate data is retained separately from approvals. No client can accept it.
create table private.diamond_migration_reviews (
  member_id uuid primary key references auth.users on delete cascade,
  snapshot jsonb not null,
  signed_transactions jsonb not null,
  submitted_at timestamptz not null default now()
);
create table private.diamond_order_reviews (
  member_id uuid not null references auth.users on delete cascade,
  tx text not null,
  claim jsonb not null,
  submitted_at timestamptz not null default now(),
  primary key (member_id, tx)
);

-- Only a separately authenticated, privileged reconciliation process may write
-- approvals. A signed-in device cannot approve its own previous balance or order.
create table private.diamond_legacy_approvals (
  member_id uuid primary key references auth.users on delete cascade,
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  reviewed_at timestamptz not null default now()
);
create table private.diamond_purchase_approvals (
  tx text primary key,
  member_id uuid not null references auth.users on delete cascade,
  source text not null check (source in ('districtWallet', 'communityOrder')),
  product text not null check (product ~ '^[A-Za-z0-9._-]{1,100}$'),
  quantity integer not null check (quantity between 1 and 10),
  environment text not null check (environment = 'Production'),
  intent_id uuid,
  installation uuid not null,
  order_ref text,
  reviewed_at timestamptz not null default now()
);
create index diamond_purchase_approvals_member on private.diamond_purchase_approvals(member_id);

-- An account deletion removes identifiable order and balance data. Only the
-- transaction digest survives, so a deleted purchase cannot be claimed again.
create table private.used_diamond_transactions (
  digest bytea primary key check (octet_length(digest) = 32)
);
create table private.diamond_orders (
  tx text primary key check (tx ~ '^[1-9][0-9]{0,19}$'),
  member_id uuid not null references auth.users on delete cascade,
  intent_id uuid unique references private.diamond_intents on delete cascade,
  source text not null check (source in ('districtWallet', 'communityOrder')),
  product text not null check (product ~ '^[A-Za-z0-9._-]{1,100}$'),
  quantity integer not null check (quantity between 1 and 10),
  environment text not null check (environment = 'Production'),
  state text not null check (state in ('settled','processing','reconciliation','declined')),
  attempt uuid,
  lease_until timestamptz,
  order_ref text,
  updated_at timestamptz not null default now(),
  check ((state = 'processing') = (attempt is not null and lease_until is not null))
);
create index diamond_orders_member on private.diamond_orders(member_id);
create unique index diamond_orders_external_ref on private.diamond_orders(order_ref)
  where source = 'communityOrder' and order_ref is not null;
create table private.diamond_spends (
  member_id uuid not null references auth.users on delete cascade,
  kind text not null check (kind in ('unlock','build')),
  item text not null,
  diamonds integer not null check (diamonds > 0),
  primary key (member_id, kind, item)
);

revoke all on private.diamond_wallets, private.diamond_intents, private.diamond_legacy_approvals,
  private.diamond_purchase_approvals, private.used_diamond_transactions, private.diamond_orders,
  private.diamond_spends, private.diamond_migration_reviews, private.diamond_order_reviews from public, anon, authenticated, service_role;

create function private.diamond_pack(product text) returns integer
language sql immutable strict set search_path = '' as $$
  select case product
    when 'uohawcxkafqpasyj' then 400 when 'mzrzpodxjhimaake' then 800
    when 'mdlygzxdpozvvlbw' then 2450 when 'dcfaerebmpzalupy' then 5150
    when 'xxxtadehqhqxgkwn' then 10800 when 'vfjqemzkpltxrhdc' then 16900
    when 'qotneepcamgqzzcw' then 29400 when 'gwnrbskxvtdqhyfm' then 42900
    when 'cwunwzuwnpqpyrgu' then 63700 end;
$$;
create function private.district_price(kind text, item text) returns integer
language sql immutable strict set search_path = '' as $$
  select case when kind = 'build' and item ~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then 120
    when kind = 'unlock' then case item when 'district-sahara' then 30 when 'district-tundra' then 45
      when 'district-rainforest' then 60 end end;
$$;

create function private.lock_diamond_wallet(actor uuid, session_key uuid) returns private.diamond_wallets
language plpgsql set search_path = '' as $$
declare w private.diamond_wallets;
begin
  perform private.lock_chat_photo_accounts(actor, actor);
  if not exists (select 1 from auth.sessions s join auth.users u on u.id = s.user_id
    join public.profiles p on p.id = u.id where s.id = session_key and u.id = actor
      and (s.not_after is null or s.not_after > now())
      and u.is_anonymous is false and u.raw_app_meta_data->>'sign_in_method' = 'device'
      and (u.banned_until is null or u.banned_until <= now()))
    or exists (select 1 from private.account_photo_deletions where member_id = actor) then
    raise exception 'auth_required' using errcode = '42501';
  end if;
  insert into private.diamond_wallets(member_id) values (actor) on conflict do nothing;
  select * into strict w from private.diamond_wallets where member_id = actor for update;
  return w;
end;
$$;

create function private.reserve_diamond_transaction(tx text) returns void
language plpgsql set search_path = '' as $$
begin
  insert into private.used_diamond_transactions(digest) values (sha256(convert_to('Sese/StoreKit/' || tx,'UTF8')))
    on conflict do nothing;
  if not found then raise exception 'ownership_conflict' using errcode = 'P0001'; end if;
end;
$$;

-- Apple proves purchases but cannot prove that a device disclosed all charges.
-- On a pristine account a fully verified, zero-remainder snapshot grants only
-- the recorded, fully paid district entitlements and cannot create spendable credit.
create function private.diamond_zero_snapshot(snapshot jsonb, evidence jsonb) returns boolean
language sql immutable strict set search_path = '' as $$
  with purchases as (
    select entry->>'transactionID' as tx, (entry->>'diamonds')::bigint as amount,
      private.diamond_pack(entry->>'productID') as price
    from jsonb_array_elements(snapshot->'purchases') as entry
  ), charges as (
    select (entry->>'diamonds')::bigint as amount, private.district_price('unlock',entry->>'id') as price
      from jsonb_array_elements(snapshot->'unlocks') as entry
    union all
    select (entry->>'diamonds')::bigint, private.district_price('build',entry->>'id')
      from jsonb_array_elements(snapshot->'districts') as entry
  )
  select exists (select 1 from purchases)
    and not exists (select 1 from purchases p where p.price is null or
      p.amount is distinct from (evidence->>p.tx)::bigint * p.price)
    and not exists (select 1 from charges c where c.amount is distinct from c.price::bigint)
    and (select sum(amount) from purchases) = (select sum(amount) from charges);
$$;

create function private.import_diamond_wallet(actor uuid, snapshot jsonb, verified_zero boolean) returns bigint
language plpgsql set search_path = '' as $$
declare
  approved jsonb;
  row_data jsonb;
  price integer;
  units integer;
  spend_kind text;
  current_balance bigint := 0;
  o private.diamond_orders;
begin
  select a.snapshot into approved from private.diamond_legacy_approvals a where a.member_id = actor;
  if (approved is not null and approved <> snapshot)
    or (approved is null and verified_zero is not true and snapshot <> '{"purchases":[],"unlocks":[],"districts":[]}'::jsonb) then
    raise exception 'migration_review';
  end if;
  for row_data in select value from jsonb_array_elements(snapshot->'purchases') loop
    price := private.diamond_pack(row_data->>'productID');
    units := (row_data->>'diamonds')::integer / price;
    if price is null or units not between 1 and 10 or units * price <> (row_data->>'diamonds')::integer then
      raise exception 'invalid_request';
    end if;
    select * into o from private.diamond_orders where tx = row_data->>'transactionID';
    if found then
      if (o.member_id,o.source,o.product,o.quantity,o.intent_id,o.state) is distinct from
        (actor,'districtWallet'::text,row_data->>'productID',units,null::uuid,'settled'::text)
        then raise exception 'ownership_conflict'; end if;
      continue;
    end if;
    perform private.reserve_diamond_transaction(row_data->>'transactionID');
    insert into private.diamond_orders(tx, member_id, source, product, quantity, environment, state)
      values (row_data->>'transactionID', actor, 'districtWallet', row_data->>'productID', units, 'Production','settled');
    current_balance := current_balance + units * price;
  end loop;
  foreach spend_kind in array array['unlock','build'] loop
    for row_data in select value from jsonb_array_elements(snapshot->(case spend_kind when 'unlock' then 'unlocks' else 'districts' end)) loop
      price := private.district_price(spend_kind, row_data->>'id');
      if price is null or price <> (row_data->>'diamonds')::integer then raise exception 'invalid_request'; end if;
      insert into private.diamond_spends values (actor, spend_kind, row_data->>'id', price) on conflict do nothing;
      if found then current_balance := current_balance - price; end if;
    end loop;
  end loop;
  if (select balance from private.diamond_wallets where member_id = actor) + current_balance < 0
    then raise exception 'insufficient_balance'; end if;
  update private.diamond_wallets set balance = balance + current_balance, migrated = true,
    imported_digest = case when snapshot <> '{"purchases":[],"unlocks":[],"districts":[]}'::jsonb
      then sha256(convert_to(snapshot::text,'UTF8')) end
    where member_id = actor returning balance into current_balance;
  return current_balance;
end;
$$;

create function public.district_wallet_action(actor uuid, session_key uuid, body jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  w record := private.lock_diamond_wallet(actor, session_key);
  op text := body->>'action';
  i private.diamond_intents;
  ref uuid;
  price integer;
  snap jsonb;
begin
  if op = 'migrate' then
    snap := body - 'action' - 'signedTransactions';
    if w.imported_digest is not null then
      if snap <> '{"purchases":[],"unlocks":[],"districts":[]}'::jsonb and
         w.imported_digest <> sha256(convert_to(snap::text,'UTF8')) then raise exception 'migration_review'; end if;
    elsif snap = '{"purchases":[],"unlocks":[],"districts":[]}'::jsonb then
      if exists (select 1 from private.diamond_migration_reviews where member_id = actor)
        or exists (select 1 from private.diamond_legacy_approvals where member_id = actor and snapshot <> snap)
        then raise exception 'migration_review'; end if;
      if not w.migrated then w.balance := private.import_diamond_wallet(actor, snap, false); end if;
    elsif exists (select 1 from private.diamond_legacy_approvals where member_id = actor and snapshot = snap)
      or (not w.migrated and private.diamond_zero_snapshot(snap, body->'signedTransactions')) then
      w.balance := private.import_diamond_wallet(actor, snap, not w.migrated and private.diamond_zero_snapshot(snap, body->'signedTransactions'));
      delete from private.diamond_migration_reviews where member_id = actor;
    else
      insert into private.diamond_migration_reviews(member_id,snapshot,signed_transactions)
        values (actor,snap,body->'signedTransactions') on conflict(member_id) do update
        set snapshot = excluded.snapshot, signed_transactions = excluded.signed_transactions, submitted_at = now();
      return jsonb_build_object('reason','migration_review');
    end if;
  elsif op = 'intent' then
    select * into i from private.diamond_intents where id = (body->>'intentID')::uuid and member_id = actor;
    if not found then raise exception 'intent_not_found'; end if;
    return jsonb_strip_nulls(jsonb_build_object('balance',w.balance,'intentID',i.id,'orderSource',i.source,
      'catalogPack',i.product,'packQuantity',i.quantity,'installationID',i.installation,'cityEdition',i.edition,'districtOrder',i.order_ref));
  elsif not w.migrated and not (op = 'prepare' and body->>'orderSource' = 'communityOrder') then raise exception 'wallet_migration_required';
  elsif op = 'prepare' then
    ref := (body->>'intentID')::uuid;
    if exists (select 1 from auth.users where id = ref) then raise exception 'ownership_conflict'; end if;
    if body->>'orderSource' = 'districtWallet' and private.diamond_pack(body->>'catalogPack') is null then raise exception 'invalid_request'; end if;
    insert into private.diamond_intents(id,member_id,source,product,quantity,installation,edition,order_ref)
      values (ref,actor,body->>'orderSource',body->>'catalogPack',(body->>'packQuantity')::integer,
        (body->>'installationID')::uuid,body->>'cityEdition',body->>'districtOrder') on conflict do nothing;
    select * into i from private.diamond_intents where id = ref;
    if not found or (i.member_id,i.source,i.product,i.quantity,i.installation,i.edition,i.order_ref)
      is distinct from (actor,body->>'orderSource',body->>'catalogPack',(body->>'packQuantity')::integer,
        (body->>'installationID')::uuid,body->>'cityEdition',body->>'districtOrder') then raise exception 'ownership_conflict'; end if;
  elsif op = 'spend' then
    price := private.district_price(body->>'kind',body->>'id');
    if price is null then raise exception 'invalid_request'; end if;
    insert into private.diamond_spends values (actor,body->>'kind',body->>'id',price) on conflict do nothing;
    if found then
      if w.balance < price then raise exception 'insufficient_balance'; end if;
      update private.diamond_wallets set balance = balance - price where member_id = actor returning balance into w.balance;
    end if;
  elsif op is distinct from 'balance' then raise exception 'invalid_request';
  end if;
  return jsonb_build_object('balance',w.balance);
end;
$$;

-- Only Edge supplies apple_verified after checking a production Apple signature.
-- Replayed requests return a durable decision before any new external dispatch.
create function public.diamond_order_claim(actor uuid, session_key uuid, body jsonb, apple_verified boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  w record := private.lock_diamond_wallet(actor, session_key);
  ref uuid := (body->>'intentID')::uuid;
  tx_key text := body->>'storeTransaction';
  src text := body->>'orderSource';
  pack text := body->>'catalogPack';
  qty integer := (body->>'packQuantity')::integer;
  installation_id uuid := (body->>'installationID')::uuid;
  order_code text := body->>'districtOrder';
  unit_price integer := private.diamond_pack(pack);
  i private.diamond_intents;
  o private.diamond_orders;
  approved boolean;
  claim_token uuid;
begin
  if tx_key is null or tx_key !~ '^[1-9][0-9]{0,19}$' or (src = 'districtWallet' and unit_price is null) or qty not between 1 and 10
    or src not in ('districtWallet','communityOrder') or (src = 'districtWallet' and order_code is not null) then
    raise exception 'invalid_request';
  end if;
  if body->>'storeEnvironment' is distinct from 'Production' then raise exception 'environment_mismatch'; end if;
  if ref is null then
    if src <> 'districtWallet' then raise exception 'ownership_conflict'; end if;
  else
    select * into i from private.diamond_intents where id = ref;
    if not found or (i.member_id,i.source,i.product,i.quantity,i.installation,i.edition,i.order_ref)
      is distinct from (actor,src,pack,qty,installation_id,body->>'cityEdition',order_code) then
      raise exception 'ownership_conflict';
    end if;
  end if;
  select * into o from private.diamond_orders where tx = tx_key;
  if found then
    if (o.member_id,o.intent_id,o.source,o.product,o.quantity,o.order_ref) is distinct from
      (actor,ref,src,pack,qty,order_code) then raise exception 'ownership_conflict'; end if;
    if o.state = 'settled' then return jsonb_build_object('balance',w.balance); end if;
    if o.state = 'processing' and o.lease_until <= clock_timestamp() then
      update private.diamond_orders set state = 'reconciliation', attempt = null, lease_until = null, updated_at = now()
        where tx = tx_key;
      return jsonb_build_object('reason','reconciliation');
    end if;
    return jsonb_build_object('reason',case o.state when 'declined' then 'upstream_declined' else o.state end);
  end if;
  if src = 'districtWallet' and not w.migrated then raise exception 'wallet_migration_required'; end if;
  if exists (select 1 from private.diamond_orders where intent_id = ref or (order_code is not null and order_ref = order_code))
    then raise exception 'ownership_conflict'; end if;

  select exists (select 1 from private.diamond_purchase_approvals a where
    (a.tx,a.member_id,a.source,a.product,a.quantity,a.environment,a.intent_id,a.installation,a.order_ref)
    is not distinct from (tx_key,actor,src,pack,qty,'Production'::text,ref,installation_id,order_code)) into approved;

  if apple_verified is not true then return jsonb_build_object('verify',true); end if;
  if ref is not null and ((body->>'purchaseDate') is null or
    to_timestamp((body->>'purchaseDate')::double precision / 1000) < date_trunc('second',i.created_at))
    then raise exception 'ownership_conflict'; end if;
  -- A legacy transaction can be re-presented after its diamonds were spent.
  -- Reconciliation distinguishes a truly unfinished historical order from one
  -- already covered by a migrated ledger. New intents do not need this step.
  if ref is null and not approved then
    insert into private.diamond_order_reviews(member_id,tx,claim)
      values (actor,tx_key,body) on conflict(member_id,tx) do nothing;
    return jsonb_build_object('reason','migration_review');
  end if;
  perform private.reserve_diamond_transaction(tx_key);
  if src = 'districtWallet' then
    insert into private.diamond_orders(tx,member_id,intent_id,source,product,quantity,environment,state)
      values(tx_key,actor,ref,src,pack,qty,'Production','settled');
    update private.diamond_wallets set balance = balance + qty * unit_price
      where member_id = actor returning balance into w.balance;
    return jsonb_build_object('balance',w.balance);
  end if;
  claim_token := gen_random_uuid();
  insert into private.diamond_orders(tx,member_id,intent_id,source,product,quantity,environment,state,attempt,lease_until,order_ref)
    values(tx_key,actor,ref,src,pack,qty,'Production','processing',claim_token,now() + interval '45 seconds',order_code);
  return jsonb_build_object('dispatch',claim_token);
exception when unique_violation then raise exception 'ownership_conflict';
end;
$$;

create function public.diamond_order_finish(tx_key text, claim_token uuid, outcome text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid;
  amount bigint;
begin
  if outcome not in ('settled','reconciliation','declined') or outcome is null then raise exception 'invalid_request'; end if;
  update private.diamond_orders set state = outcome, attempt = null, lease_until = null, updated_at = now()
    where tx = tx_key and source = 'communityOrder' and state = 'processing' and attempt = claim_token
      and lease_until > clock_timestamp()
    returning member_id into actor;
  if not found then raise exception 'reconciliation'; end if;
  if outcome <> 'settled' then return jsonb_build_object('reason',case outcome when 'declined' then 'upstream_declined' else outcome end); end if;
  select balance into strict amount from private.diamond_wallets where member_id = actor;
  return jsonb_build_object('balance',amount);
end;
$$;

revoke all on function private.diamond_pack(text), private.district_price(text,text),
  private.lock_diamond_wallet(uuid,uuid), private.reserve_diamond_transaction(text), private.import_diamond_wallet(uuid,jsonb,boolean), private.diamond_zero_snapshot(jsonb,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.district_wallet_action(uuid,uuid,jsonb), public.diamond_order_claim(uuid,uuid,jsonb,boolean),
  public.diamond_order_finish(text,uuid,text) from public, anon, authenticated;
grant execute on function public.district_wallet_action(uuid,uuid,jsonb), public.diamond_order_claim(uuid,uuid,jsonb,boolean),
  public.diamond_order_finish(text,uuid,text) to service_role;
