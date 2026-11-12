create table private.release_settings (
  singleton boolean primary key default true check (singleton),
  agreement_revision text check (char_length(agreement_revision) between 1 and 160)
);
insert into private.release_settings (singleton) values (true);
revoke all on private.release_settings from public, anon, authenticated;

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
    on conflict (member_id) do update set revision = excluded.revision, accepted_at = now()
    where consents.revision is distinct from excluded.revision;
  return jsonb_build_object('code', 0, 'message', 'ok', 'data', '{}'::jsonb);
end;
$$;

update public.catalog
set image_url = 'https://lumiere-a.akamaihd.net/v1/images/pp_zootopia_herobanner_19736_65e255b5.jpeg?region=0%2C0%2C2048%2C878&width=1536'
where kind = 'Film Clip';
