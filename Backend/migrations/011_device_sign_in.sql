create table private.device_provisioning_limit (
  singleton boolean primary key default true check (singleton),
  minute_started_at timestamptz not null,
  attempts integer not null check (attempts between 1 and 30)
);
revoke all on private.device_provisioning_limit from public, anon, authenticated;

create function public.reserve_device_provisioning(agreement_revision text) returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  active_revision text;
  current_minute timestamptz := date_trunc('minute', statement_timestamp());
  reserved boolean;
begin
  select r.agreement_revision into active_revision from private.release_settings r where r.singleton;
  if active_revision is null or agreement_revision is distinct from active_revision then
    return 409;
  end if;

  insert into private.device_provisioning_limit as q (minute_started_at, attempts)
  values (current_minute, 1)
  on conflict (singleton) do update
  set minute_started_at = excluded.minute_started_at,
      attempts = case when q.minute_started_at = excluded.minute_started_at then q.attempts + 1 else 1 end
  where q.minute_started_at < excluded.minute_started_at
     or (q.minute_started_at = excluded.minute_started_at and q.attempts < 30)
  returning true into reserved;

  return case when reserved is true then 204 else 429 end;
end;
$$;

revoke all on function public.reserve_device_provisioning(text) from public, anon, authenticated;
grant execute on function public.reserve_device_provisioning(text) to service_role;

create or replace function public.bootstrap(agreement_revision text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  member uuid := auth.uid();
  active_revision text;
begin
  if member is null or not exists (
    select 1 from auth.users u
    where u.id = member and u.is_anonymous is false
      and u.raw_app_meta_data ->> 'sign_in_method' = 'device'
  ) then
    raise exception 'A device account is required' using errcode = '42501';
  end if;

  select r.agreement_revision into active_revision from private.release_settings r where r.singleton;
  if active_revision is null or agreement_revision is distinct from active_revision then
    raise exception 'Current agreements are required';
  end if;
  insert into public.profiles(id) values (member) on conflict do nothing;
  insert into public.consents(member_id, revision) values (member, agreement_revision)
    on conflict (member_id, revision) do nothing;
  return jsonb_build_object('code', 0, 'message', 'ok', 'data', '{}'::jsonb);
end;
$$;
