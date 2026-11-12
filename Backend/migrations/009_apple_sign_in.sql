create or replace function public.bootstrap(agreement_revision text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  member uuid := auth.uid();
  active_revision text;
begin
  if member is null or not exists (
    select 1 from auth.users u join auth.identities i on i.user_id = u.id
    where u.id = member and u.is_anonymous is false and i.provider = 'apple'
  ) then
    raise exception 'An Apple account is required' using errcode = '42501';
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
