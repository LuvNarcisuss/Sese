-- A member's visibility preferences and the moderation evidence have separate lifetimes.
alter table public.reports add column withdrawn_at timestamptz;
create table private.video_hides (
  actor uuid not null references public.profiles on delete cascade,
  target_key text not null,
  label text not null,
  reason text not null,
  reported_at timestamptz not null,
  primary key (actor, target_key)
);
create index video_hides_history on private.video_hides (actor, reported_at desc, target_key);
create table private.block_notices (
  id uuid primary key default gen_random_uuid(),
  actor uuid not null references public.profiles on delete cascade,
  peer uuid not null,
  comment_id uuid,
  comment_excerpt text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);
revoke all on private.video_hides, private.block_notices from public, anon, authenticated;
grant usage on schema private to service_role;
grant select, update (reviewed_at) on private.block_notices to service_role;

-- A private member's display name is never disclosed by the management list.
alter table public.blocks add column label text not null default 'City Resident',
  add column created_at timestamptz not null default now(),
  add column source_comment uuid;
update public.blocks b set label = p.display_name from public.profiles p
  where p.id = b.target_id and p.discoverable;

create function private.block_label() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  select case when p.discoverable then p.display_name else 'City Resident' end into strict new.label
    from public.profiles p where p.id = new.target_id;
  return new;
end;
$$;
create trigger block_set_label before insert on public.blocks for each row execute function private.block_label();

create function private.notify_moderator_of_block() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into private.block_notices(actor, peer, comment_id, comment_excerpt)
  values (new.blocker_id, new.target_id, new.source_comment,
    (select c.body from public.comments c where c.id = new.source_comment and c.author_id = new.target_id));
  return null;
end;
$$;
create trigger block_notify after insert on public.blocks for each row execute function private.notify_moderator_of_block();

create function private.block_member(peer uuid, comment uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if actor is null or peer is null or actor = peer then raise exception 'Invalid member'; end if;
  if exists (select 1 from public.blocks b where b.blocker_id = actor and b.target_id = peer) then return; end if;
  if comment is not null then
    if not exists (select 1 from public.comments c join public.catalog v on v.id = c.catalog_id
      where c.id = comment and c.author_id = peer and not private.is_blocked(peer)
        and (v.publisher_id is null or not private.is_blocked(v.publisher_id))
        and not exists (select 1 from private.video_hides h where h.actor = (select auth.uid()) and h.target_key = 'catalog:' || v.id))
    then raise exception 'Comment unavailable'; end if;
  elsif not exists (select 1 from public.profiles p where p.id = peer and p.discoverable and not private.is_blocked(peer)) then
    raise exception 'Member unavailable';
  end if;
  insert into public.blocks (blocker_id, target_id, source_comment)
    values (actor, peer, comment) on conflict (blocker_id, target_id) do nothing;
end;
$$;
create function public.block_member(peer uuid, comment uuid default null) returns void
language sql set search_path = '' as $$ select private.block_member(peer, comment); $$;

create function private.video_hidden(item text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from private.video_hides h where h.actor = (select auth.uid()) and h.target_key = item);
$$;
-- Copy the most recent legacy report for each viewer and video. Keep the original reports intact.
create view private.reported_videos as
  select r.id, r.reporter_id, r.created_at, r.reason, 'catalog:' || c.id as target_key, c.title as label
  from public.reports r join public.catalog c on c.id = r.catalog_id where c.kind in ('Film Clip', 'Cosplay Video')
  union all
  select r.id, r.reporter_id, r.created_at, r.reason, 'work:' || w.id, w.title
  from public.reports r join public.works w on w.id = r.work_id
  union all
  select r.id, r.reporter_id, r.created_at, r.reason, 'cosplay:' || p.id, p.title
  from public.reports r join public.cosplay_posts p on p.id = r.cosplay_post_id where p.media_kind = 'video';
revoke all on private.reported_videos from public, anon, authenticated;
insert into private.video_hides(actor, target_key, label, reason, reported_at)
  select distinct on (reporter_id, target_key) reporter_id, target_key, label, reason, created_at
  from private.reported_videos order by reporter_id, target_key, created_at desc, id desc;

create function private.hide_reported_video() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into private.video_hides(actor, target_key, label, reason, reported_at)
    select reporter_id, target_key, label, reason, created_at from private.reported_videos where id = new.id
    on conflict (actor, target_key) do nothing;
  return null;
end;
$$;
create trigger report_hide_video after insert on public.reports for each row execute function private.hide_reported_video();

-- Restrictive policies compose with normal ownership, publication, and blocking policies.
create policy catalog_video_visibility on public.catalog as restrictive for select to authenticated
  using (not private.video_hidden('catalog:' || id));
create policy work_video_visibility on public.works as restrictive for select to authenticated
  using (not private.video_hidden('work:' || id));
create policy cosplay_video_visibility on public.cosplay_posts as restrictive for select to authenticated
  using (not private.video_hidden('cosplay:' || id));

-- Serialize retries for the same viewer and target; old app versions can still insert reports.
create function public.submit_video_report(target_kind text, item_key text, report_reason text) returns void
language plpgsql security invoker set search_path = '' as $$
declare actor uuid := auth.uid(); k text;
begin
  if actor is null or item_key is null or target_kind not in ('catalog','work','cosplay') or target_kind is null then
    raise exception 'Invalid report target';
  end if;
  if target_kind <> 'catalog' then item_key := item_key::uuid::text; end if;
  k := target_kind || ':' || item_key;
  perform pg_advisory_xact_lock(hashtextextended(actor::text || ':' || k, 0));
  if private.video_hidden(k) then return; end if;
  case target_kind
  when 'catalog' then
    if not exists (select 1 from public.catalog c where c.id = item_key and c.kind in ('Film Clip','Cosplay Video')
      and c.publisher_id is distinct from actor) then
      raise exception 'Item unavailable';
    end if;
    insert into public.reports(catalog_id, reason) values (item_key, report_reason);
  when 'work' then
    if not exists (select 1 from public.works w where w.id = item_key::uuid and w.owner_id <> actor) then
      raise exception 'Video unavailable';
    end if;
    insert into public.reports(work_id, reason) values (item_key::uuid, report_reason);
  when 'cosplay' then
    if not exists (select 1 from public.cosplay_posts p where p.id = item_key::uuid
      and p.media_kind = 'video' and p.status = 'approved' and p.owner_id <> actor) then
      raise exception 'Video unavailable';
    end if;
    insert into public.reports(cosplay_post_id, reason) values (item_key::uuid, report_reason);
  end case;
  if not private.video_hidden(k) then raise exception 'Video could not be hidden'; end if;
end;
$$;

-- Preserve the normal visibility checks for reports coming from older app versions.
alter policy reports_add on public.reports with check (reporter_id = (select auth.uid()) and
  (catalog_id is null or exists (select 1 from public.catalog c where c.id = catalog_id and c.publisher_id is distinct from (select auth.uid()))) and
  (work_id is null or exists (select 1 from public.works w where w.id = work_id and w.owner_id <> (select auth.uid()))) and
  (message_id is null or exists (select 1 from public.messages m where m.id = message_id)) and
  (comment_id is null or exists (select 1 from public.comments c where c.id = comment_id)) and
  (cosplay_post_id is null or exists (select 1 from public.cosplay_posts p where p.id = cosplay_post_id
    and p.owner_id <> (select auth.uid()) and p.status = 'approved')));

create function private.withdraw_video_report(entry_key text) returns void
language plpgsql security definer set search_path = '' as $$
declare viewer uuid := auth.uid();
begin
  if viewer is null then raise exception 'Sign in first'; end if;
  perform pg_advisory_xact_lock(hashtextextended(viewer::text || ':' || entry_key, 0));
  delete from private.video_hides h where h.actor = viewer and h.target_key = entry_key;
  if found then
    update public.reports r set withdrawn_at = statement_timestamp()
    where r.reporter_id = viewer and r.withdrawn_at is null and
      (entry_key = 'catalog:' || r.catalog_id or entry_key = 'work:' || r.work_id::text
        or entry_key = 'cosplay:' || r.cosplay_post_id::text);
  end if;
end;
$$;
create function public.withdraw_video_report(entry_key text) returns void
language sql set search_path = '' as $$ select private.withdraw_video_report(entry_key); $$;

create function private.safety_history(entry_kind text, page_offset integer)
returns table (target_key text, label text, detail text)
language sql stable security definer set search_path = '' as $$
  select s.k, s.title, s.description from (
    select h.target_key k, h.label title,
      h.reason || ' · ' || h.target_key description, h.reported_at t
    from private.video_hides h where entry_kind = 'report' and h.actor = (select auth.uid())
    union all
    select b.target_id::text, b.label,
      'Member ' || b.target_id::text,
      b.created_at
    from public.blocks b where entry_kind = 'block' and b.blocker_id = (select auth.uid())
  ) s order by s.t desc, s.k limit 100 offset greatest(page_offset,0);
$$;
create function public.safety_history(entry_kind text, page_offset integer default 0)
returns table (target_key text, label text, detail text)
language sql stable set search_path = '' as $$ select * from private.safety_history(entry_kind,page_offset); $$;

revoke all on function private.block_label(), private.notify_moderator_of_block(), private.hide_reported_video()
  from public, anon, authenticated;
revoke all on function private.block_member(uuid,uuid), public.block_member(uuid,uuid), private.video_hidden(text),
  public.submit_video_report(text,text,text), private.withdraw_video_report(text), public.withdraw_video_report(text),
  private.safety_history(text,integer), public.safety_history(text,integer) from public, anon, authenticated;
grant execute on function private.block_member(uuid,uuid), public.block_member(uuid,uuid), private.video_hidden(text),
  public.submit_video_report(text,text,text), private.withdraw_video_report(text), public.withdraw_video_report(text),
  private.safety_history(text,integer), public.safety_history(text,integer) to authenticated;
notify pgrst, 'reload schema';
