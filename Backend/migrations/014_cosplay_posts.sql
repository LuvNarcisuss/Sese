create table public.cosplay_posts (
  id uuid primary key,
  owner_id uuid not null references public.profiles on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 80),
  caption text not null check (char_length(caption) <= 350),
  media_kind text not null check (media_kind in ('photo', 'video')),
  media_path text not null unique,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'removed')),
  created_at timestamptz not null default now(),
  constraint cosplay_media_path check (media_path = owner_id::text || '/' || id::text ||
    case media_kind when 'photo' then '.jpg' else '.mp4' end)
);

create index cosplay_posts_owner_created_idx on public.cosplay_posts (owner_id, created_at desc, id desc);
create index cosplay_posts_approved_idx on public.cosplay_posts (created_at desc, id desc) where status = 'approved';
alter table public.cosplay_posts enable row level security;
revoke all on public.cosplay_posts from public, anon, authenticated;
grant select on public.cosplay_posts to authenticated;
grant all on public.cosplay_posts to service_role;
create policy cosplay_posts_read on public.cosplay_posts for select to authenticated using (
  owner_id = (select auth.uid()) or
  (status = 'approved' and not private.is_blocked(owner_id) and
    exists (select 1 from public.profiles p where p.id = owner_id and p.discoverable))
);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('cosplay-media', 'cosplay-media', false, 6291456, array['image/jpeg', 'video/mp4']);

create function private.cosplay_upload_allowed(object_name text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
begin
  if actor is null or split_part(object_name, '/', 1) <> actor::text or
     object_name !~ '^[0-9a-f-]{36}/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}[.](jpg|mp4)$' then
    return false;
  end if;
  perform private.lock_chat_photo_accounts(actor, actor);
  return not exists (select 1 from private.account_photo_deletions d where d.member_id = actor)
    and exists (select 1 from public.profiles p where p.id = actor)
    and not exists (select 1 from public.cosplay_posts p where p.media_path = object_name);
end;
$$;

create function private.cosplay_media_visible(object_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select (select auth.uid()) is not null and
    not exists (select 1 from private.account_photo_deletions d
      where d.member_id::text = split_part(object_name, '/', 1)) and (
    split_part(object_name, '/', 1) = (select auth.uid())::text or
    exists (select 1 from public.cosplay_posts p join public.profiles a on a.id = p.owner_id
      where p.media_path = object_name and p.status = 'approved' and a.discoverable
        and not private.is_blocked(p.owner_id))
  );
$$;

create function private.cosplay_media_removable(object_name text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
begin
  if actor is null or split_part(object_name, '/', 1) <> actor::text then return false; end if;
  perform private.lock_chat_photo_accounts(actor, actor);
  return exists (select 1 from private.account_photo_deletions d where d.member_id = actor)
    or not exists (select 1 from public.cosplay_posts p where p.media_path = object_name and p.status <> 'removed');
end;
$$;

revoke all on function private.cosplay_upload_allowed(text), private.cosplay_media_visible(text),
  private.cosplay_media_removable(text) from public, anon, authenticated;
grant execute on function private.cosplay_upload_allowed(text), private.cosplay_media_visible(text),
  private.cosplay_media_removable(text) to authenticated;

create policy cosplay_media_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'cosplay-media' and private.cosplay_upload_allowed(name)
);
create policy cosplay_media_select on storage.objects for select to authenticated using (
  bucket_id = 'cosplay-media' and (
    (storage.allow_any_operation(array['object.get_authenticated', 'object.get_authenticated_info'])
      and private.cosplay_media_visible(name))
    or (storage.allow_any_operation(array['object.delete', 'object.delete_many'])
      and private.cosplay_media_removable(name))
  )
);
create policy cosplay_media_remove on storage.objects for delete to authenticated using (
  bucket_id = 'cosplay-media' and private.cosplay_media_removable(name)
);

create function public.submit_cosplay_post(post_id uuid, post_title text, post_caption text, kind text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  object_name text;
  mime text;
  saved public.cosplay_posts;
begin
  if actor is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if post_id is null or kind is null or kind not in ('photo', 'video')
     or post_title is null or char_length(btrim(post_title)) not between 1 and 80
     or post_caption is null or char_length(post_caption) > 350 then
    raise exception 'Invalid cosplay post' using errcode = '22023';
  end if;
  perform private.lock_chat_photo_accounts(actor, actor);
  if exists (select 1 from private.account_photo_deletions d where d.member_id = actor) then
    raise exception 'This account is being deleted' using errcode = '42501';
  end if;
  object_name := actor::text || '/' || post_id::text || case kind when 'photo' then '.jpg' else '.mp4' end;
  mime := case kind when 'photo' then 'image/jpeg' else 'video/mp4' end;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'cosplay-media'
      and o.name = object_name and o.owner_id = actor::text and o.metadata->>'mimetype' = mime
      and (o.metadata->>'size')::bigint between 1 and 6291456) then
    raise exception 'The media upload is incomplete' using errcode = '22023';
  end if;
  insert into public.cosplay_posts (id, owner_id, title, caption, media_kind, media_path)
    values (post_id, actor, btrim(post_title), post_caption, kind, object_name)
    on conflict (id) do nothing;
  select * into saved from public.cosplay_posts p where p.id = post_id;
  if not found or saved.owner_id <> actor or saved.title <> btrim(post_title)
     or saved.caption <> post_caption or saved.media_kind <> kind or saved.status = 'removed' then
    raise exception 'This submission already has different content' using errcode = '22023';
  end if;
end;
$$;

create function public.hide_cosplay_post(post_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if actor is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  perform private.lock_chat_photo_accounts(actor, actor);
  update public.cosplay_posts set status = 'removed' where id = post_id and owner_id = actor;
end;
$$;

create function public.finish_cosplay_post_removal(post_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if actor is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  perform private.lock_chat_photo_accounts(actor, actor);
  if exists (select 1 from public.cosplay_posts p join storage.objects o
      on o.bucket_id = 'cosplay-media' and o.name = p.media_path where p.id = post_id and p.owner_id = actor) then
    raise exception 'Media cleanup is incomplete' using errcode = '22023';
  end if;
  delete from public.cosplay_posts where id = post_id and owner_id = actor and status = 'removed';
end;
$$;

create function public.begin_account_cosplay_cleanup() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if actor is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  perform private.lock_chat_photo_accounts(actor, actor);
  insert into private.account_photo_deletions(member_id) values (actor) on conflict do nothing;
  return (select coalesce(jsonb_agg(o.name order by o.name), '[]'::jsonb) from (
    select name from storage.objects where bucket_id = 'cosplay-media'
      and split_part(name, '/', 1) = actor::text order by name limit 100
  ) o);
end;
$$;

create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
declare member uuid := auth.uid();
begin
  if member is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  perform private.lock_chat_photo_accounts(member, member);
  if exists (select 1 from storage.objects where
    (bucket_id = 'chat-photos' and member::text in (split_part(name, '/', 1), split_part(name, '/', 2))) or
    (bucket_id = 'cosplay-media' and split_part(name, '/', 1) = member::text)
  ) then
    raise exception 'Media cleanup is incomplete' using errcode = '22023';
  end if;
  delete from auth.users where id = member;
end;
$$;

revoke all on function public.submit_cosplay_post(uuid, text, text, text), public.hide_cosplay_post(uuid),
  public.finish_cosplay_post_removal(uuid), public.begin_account_cosplay_cleanup() from public, anon, authenticated;
grant execute on function public.submit_cosplay_post(uuid, text, text, text), public.hide_cosplay_post(uuid),
  public.finish_cosplay_post_removal(uuid), public.begin_account_cosplay_cleanup() to authenticated;

alter table public.reports add column cosplay_post_id uuid references public.cosplay_posts on delete cascade;
alter table public.reports drop constraint report_one_target;
alter table public.reports add constraint report_one_target
  check (num_nonnulls(reported_id, catalog_id, comment_id, message_id, work_id, cosplay_post_id) = 1);
grant insert (cosplay_post_id) on public.reports to authenticated;
alter policy reports_add on public.reports with check (reporter_id = (select auth.uid()) and
  (message_id is null or exists (select 1 from public.messages m where m.id = message_id)) and
  (comment_id is null or exists (select 1 from public.comments c where c.id = comment_id)) and
  (work_id is null or exists (select 1 from public.works w where w.id = work_id)) and
  (cosplay_post_id is null or exists (select 1 from public.cosplay_posts p where p.id = cosplay_post_id
    and p.owner_id <> (select auth.uid()) and p.status = 'approved')));
