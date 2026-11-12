alter table public.consents
  drop constraint consents_pkey,
  add primary key (member_id, revision);

create or replace function public.bootstrap(agreement_revision text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  member uuid := auth.uid();
  active_revision text;
begin
  select r.agreement_revision into active_revision from private.release_settings r where r.singleton;
  if member is null or active_revision is null or agreement_revision is distinct from active_revision then
    raise exception 'Current agreements are required';
  end if;
  insert into public.profiles(id) values (member) on conflict do nothing;
  insert into public.consents(member_id, revision) values (member, agreement_revision)
    on conflict (member_id, revision) do nothing;
  return jsonb_build_object('code', 0, 'message', 'ok', 'data', '{}'::jsonb);
end;
$$;
