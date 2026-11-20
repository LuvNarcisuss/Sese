-- Moderation receipts survive removal of the reported item. Only the actor's
-- active comment reports are exposed through the account-scoped history RPC.
alter table public.reports add column source_key text;
alter table public.blocks add column source_key text;
alter table private.block_notices add column source_key text, add column source_excerpt text;

create function private.moderation_excerpt(item text) returns text
language sql stable set search_path = '' as $$
  select case split_part(item, ':', 1)
    when 'comment' then (select body from public.comments where 'comment:' || id = item)
    when 'message' then (select body from public.messages where 'message:' || id = item)
    when 'catalog' then (select concat_ws(' · ', title, description) from public.catalog where 'catalog:' || id = item)
    when 'work' then (select concat_ws(' · ', title, caption) from public.works where 'work:' || id = item)
    when 'cosplay' then (select concat_ws(' · ', title, caption) from public.cosplay_posts where 'cosplay:' || id = item)
    when 'member' then (select display_name from public.profiles where 'member:' || id = item)
  end;
$$;
revoke all on function private.moderation_excerpt(text) from public, anon, authenticated;

create table private.report_receipts (
  report_id uuid primary key,
  actor uuid not null references public.profiles on delete cascade,
  target_key text not null, author_id uuid, source_key text,
  excerpt text not null, source_excerpt text, reason text not null,
  reported_at timestamptz not null, withdrawn_at timestamptz
);
create index report_receipts_active on private.report_receipts(actor, target_key, reported_at desc) where withdrawn_at is null;
revoke all on private.report_receipts from public, anon, authenticated;
grant select on private.report_receipts to service_role;

create view private.report_snapshot as
  select r.id, r.reporter_id, k.target, coalesce(c.author_id,m.sender_id,v.publisher_id,w.owner_id,p.owner_id,r.reported_id) as author_id,
    coalesce(r.source_key, 'catalog:' || c.catalog_id) as source,
    coalesce(private.moderation_excerpt(k.target),'Unavailable') as excerpt,
    private.moderation_excerpt(coalesce(r.source_key,'catalog:' || c.catalog_id)) as source_excerpt,
    r.reason, r.created_at, r.withdrawn_at
  from public.reports r
  cross join lateral (select coalesce('comment:' || r.comment_id, 'message:' || r.message_id, 'member:' || r.reported_id,
    'catalog:' || r.catalog_id,'work:' || r.work_id,'cosplay:' || r.cosplay_post_id) as target) k
  left join public.comments c on c.id=r.comment_id left join public.messages m on m.id=r.message_id
  left join public.catalog v on v.id=r.catalog_id left join public.works w on w.id=r.work_id
  left join public.cosplay_posts p on p.id=r.cosplay_post_id;
revoke all on private.report_snapshot from public, anon, authenticated;
insert into private.report_receipts select * from private.report_snapshot;

create function private.record_report_receipt() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op='INSERT' then
    insert into private.report_receipts select * from private.report_snapshot where id=new.id;
  else
    update private.report_receipts set withdrawn_at=new.withdrawn_at where report_id=new.id;
  end if;
  return null;
end;
$$;
revoke all on function private.record_report_receipt() from public, anon, authenticated;
create trigger report_receipt after insert or update of withdrawn_at on public.reports
  for each row execute function private.record_report_receipt();

create function private.comment_hidden(item uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select from private.report_receipts where actor=(select auth.uid())
    and target_key='comment:' || item and withdrawn_at is null and author_id is distinct from actor);
$$;
create policy comment_report_visibility on public.comments as restrictive for select to authenticated
  using (not private.comment_hidden(id));

-- The caller must be able to read the actual originating item through its own RLS.
create function private.peer_available(peer uuid, source text) returns boolean
language sql stable security invoker set search_path = '' as $$
  select peer <> (select auth.uid()) and not private.is_blocked(peer) and case
    when source is null then exists(select from public.profiles p where p.id=peer) or
      exists(select from public.messages m where (m.sender_id=peer and m.recipient_id=(select auth.uid()))
        or (m.recipient_id=peer and m.sender_id=(select auth.uid())))
    when source like 'comment:%' then exists(select from public.comments where 'comment:' || id=source and author_id=peer)
    when source like 'catalog:%' then exists(select from public.catalog where 'catalog:' || id=source and publisher_id=peer)
    when source like 'work:%' then exists(select from public.works where 'work:' || id=source and owner_id=peer)
    when source like 'cosplay:%' then exists(select from public.cosplay_posts where 'cosplay:' || id=source and owner_id=peer)
    when source like 'message:%' then exists(select from public.messages where 'message:' || id=source and sender_id=peer)
    else false end;
$$;

grant insert(source_key) on public.reports, public.blocks to authenticated;
create policy report_target_eligibility on public.reports as restrictive for insert to authenticated with check (
  (case when reported_id is null then source_key is null else private.peer_available(reported_id,source_key) end)
  and (comment_id is null or exists(select from public.comments c where c.id=comment_id and c.author_id is distinct from (select auth.uid())))
  and (message_id is null or exists(select from public.messages m where m.id=message_id and m.sender_id<>(select auth.uid())))
);
create policy block_target_eligibility on public.blocks as restrictive for insert to authenticated
  with check (private.peer_available(target_id,source_key));

create function public.block_from_source(peer uuid, source text) returns void
language plpgsql security invoker set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text || ':block:' || peer,0));
  if exists(select from public.blocks where blocker_id=(select auth.uid()) and target_id=peer) then return; end if;
  if not coalesce(private.peer_available(peer,source),false) then raise exception 'Member unavailable'; end if;
  insert into public.blocks(target_id,source_key) values(peer,source);
end;
$$;

-- Older clients keep the same RPC and receive the same validation.
create or replace function private.block_member(peer uuid, comment uuid) returns void
language sql security invoker set search_path = '' as $$
  select public.block_from_source(peer,'comment:' || comment);
$$;
create or replace function private.block_label() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  select case when p.discoverable then p.display_name else 'City Resident' end into strict new.label
    from public.profiles p where p.id=new.target_id;
  if new.source_key like 'comment:%' then new.source_comment := substring(new.source_key from 9)::uuid; end if;
  return new;
end;
$$;
create or replace function private.notify_moderator_of_block() returns trigger
language plpgsql security definer set search_path = '' as $$
declare excerpt text := private.moderation_excerpt(new.source_key);
begin
  insert into private.block_notices(actor,peer,comment_id,comment_excerpt,source_key,source_excerpt)
  values(new.blocker_id,new.target_id,new.source_comment,case when new.source_comment is not null then excerpt end,new.source_key,excerpt);
  return null;
end;
$$;

create function public.submit_comment_report(item uuid, report_reason text) returns void
language plpgsql security invoker set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text || ':comment:' || item,0));
  if private.comment_hidden(item) then return; end if;
  insert into public.reports(comment_id,reason) values(item,report_reason);
end;
$$;
create function private.withdraw_comment_report(item uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text || ':comment:' || item,0));
  update public.reports set withdrawn_at=statement_timestamp()
    where reporter_id=(select auth.uid()) and comment_id=item and withdrawn_at is null;
  update private.report_receipts set withdrawn_at=statement_timestamp()
    where actor=(select auth.uid()) and target_key='comment:' || item and withdrawn_at is null;
end;
$$;
create function public.withdraw_comment_report(item uuid) returns void
language sql set search_path = '' as $$ select private.withdraw_comment_report(item); $$;

create function private.reported_comment_history(page_offset integer)
returns table(target_key text, label text, detail text)
language sql stable security definer set search_path = '' as $$
  select h.target_key,h.excerpt,concat_ws(' · ',case when h.author_id is null then 'Sese Editorial'
    when p.discoverable then p.display_name else 'City Resident' end,h.reason)
  from (select distinct on (r.target_key) r.* from private.report_receipts r
    where actor=(select auth.uid()) and r.target_key like 'comment:%' and withdrawn_at is null and author_id is distinct from actor
    order by r.target_key,r.reported_at desc,r.report_id desc) h
  left join public.profiles p on p.id=h.author_id
  order by h.reported_at desc,h.target_key limit 100 offset greatest(page_offset,0);
$$;
create function public.reported_comment_history(page_offset integer default 0)
returns table(target_key text, label text, detail text)
language sql set search_path = '' as $$ select * from private.reported_comment_history(page_offset); $$;

-- A video can be withdrawn even after the source row and live report have gone.
create function private.withdraw_video_receipt() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update private.report_receipts set withdrawn_at=statement_timestamp()
    where actor=old.actor and target_key=old.target_key and withdrawn_at is null;
  return null;
end;
$$;
revoke all on function private.withdraw_video_receipt() from public, anon, authenticated;
create trigger video_receipt_withdraw after delete on private.video_hides for each row execute function private.withdraw_video_receipt();

revoke all on function private.comment_hidden(uuid),private.peer_available(uuid,text),public.block_from_source(uuid,text),
  public.submit_comment_report(uuid,text),private.withdraw_comment_report(uuid),public.withdraw_comment_report(uuid),
  private.reported_comment_history(integer),public.reported_comment_history(integer) from public,anon,authenticated;
grant execute on function private.comment_hidden(uuid),private.peer_available(uuid,text),public.block_from_source(uuid,text),
  public.submit_comment_report(uuid,text),private.withdraw_comment_report(uuid),public.withdraw_comment_report(uuid),
  private.reported_comment_history(integer),public.reported_comment_history(integer) to authenticated;

create or replace function private.short_counts(items text[])
returns table (catalog_id text, likes bigint, comments bigint, saves bigint, shares bigint, editorial_baseline boolean)
language sql stable security definer set search_path = '' as $$
  select c.id,
    r.likes + coalesce(b.likes, 0),
    (select count(*) from public.comments x where x.catalog_id = c.id and not private.is_blocked(x.author_id) and not private.comment_hidden(x.id)),
    r.saves + coalesce(b.saves, 0),
    (select count(*) from private.short_share_events s where s.catalog_id = c.id) + coalesce(b.shares, 0),
    b.catalog_id is not null
  from public.catalog c
  left join private.short_editorial_baselines b on b.catalog_id = c.id
  cross join lateral (
    select count(*) filter (where kind = 'like') as likes, count(*) filter (where kind = 'save') as saves
    from public.reactions reaction where reaction.catalog_id = c.id
  ) r
  where (select auth.uid()) is not null and cardinality(items) <= 100 and c.id = any(items)
    and c.kind in ('Film Clip', 'Cosplay Video') and c.media_url is not null
    and not private.video_hidden('catalog:' || c.id)
    and (c.publisher_id is null or not private.is_blocked(c.publisher_id));
$$;

create or replace function private.record_short_share(item text, event uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
begin
  if actor is null or event is null or not exists (
    select 1 from public.catalog c where c.id = item and c.kind in ('Film Clip', 'Cosplay Video')
      and not private.video_hidden('catalog:' || c.id) and c.media_url is not null and (c.publisher_id is null or not private.is_blocked(c.publisher_id))
  ) then
    raise exception 'Short is unavailable';
  end if;
  insert into private.short_share_events (member_id, event_id, catalog_id) values (actor, event, item)
    on conflict (member_id, event_id) do nothing;
end;
$$;

-- Keep the same submission ID when a user retries after losing the response.
alter table public.reports add column request_key uuid;
create unique index report_request on public.reports(reporter_id,request_key) where request_key is not null;
grant insert(request_key) on public.reports to authenticated;
create function public.submit_item_report(target_type text, item text, source text, report_reason text, request_id uuid)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  if request_id is null or item is null or target_type is null or target_type not in ('member','message','catalog','cosplay') then
    raise exception 'Invalid report';
  end if;
  insert into public.reports(reported_id,message_id,catalog_id,cosplay_post_id,source_key,reason,request_key)
  values(case when target_type='member' then item::uuid end,case when target_type='message' then item::uuid end,
    case when target_type='catalog' then item end,case when target_type='cosplay' then item::uuid end,
    source,report_reason,request_id) on conflict do nothing;
end;
$$;
revoke all on function public.submit_item_report(text,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.submit_item_report(text,text,text,text,uuid) to authenticated;
notify pgrst, 'reload schema';
