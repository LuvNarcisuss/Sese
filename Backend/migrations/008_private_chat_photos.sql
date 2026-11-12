alter table public.messages add column photo_path text;
alter table public.messages add constraint message_photo_path check (
  photo_path is null or
  (body = 'Photo' and photo_path = sender_id::text || '/' || recipient_id::text || '/' || id::text || '.jpg')
);
create unique index messages_photo_path_idx on public.messages(photo_path) where photo_path is not null;

create table private.account_photo_deletions (
  member_id uuid primary key references auth.users on delete cascade
);
revoke all on private.account_photo_deletions from public, anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-photos', 'chat-photos', false, 2097152, array['image/jpeg']);

create function private.lock_chat_photo_accounts(first_id uuid, second_id uuid) returns void
language plpgsql set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('chat-photo:' || least(first_id, second_id)::text, 0));
  if first_id <> second_id then
    perform pg_advisory_xact_lock(hashtextextended('chat-photo:' || greatest(first_id, second_id)::text, 0));
  end if;
end;
$$;

create function private.chat_photo_upload_allowed(object_name text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  peer uuid;
  parts text[] := string_to_array(object_name, '/');
begin
  if actor is null or array_length(parts, 1) is distinct from 3 or parts[1] is distinct from actor::text
    or parts[2] !~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
    or parts[3] !~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}[.]jpg$' then
    return false;
  end if;
  peer := parts[2]::uuid;
  perform private.lock_chat_photo_accounts(actor, peer);
  return actor <> peer and private.can_message(peer)
    and not exists (select 1 from private.account_photo_deletions where member_id in (actor, peer));
end;
$$;

create function private.chat_photo_read_allowed(object_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.messages m
    where m.photo_path = object_name and (select auth.uid()) in (m.sender_id, m.recipient_id)
      and not private.is_blocked(case when m.sender_id = (select auth.uid()) then m.recipient_id else m.sender_id end)
      and not exists (select 1 from private.account_photo_deletions where member_id in (m.sender_id, m.recipient_id))
  ) or (
    split_part(object_name, '/', 1) = (select auth.uid())::text
    and not exists (select 1 from public.messages where photo_path = object_name)
    and not exists (
      select 1 from private.account_photo_deletions
      where member_id::text in (split_part(object_name, '/', 1), split_part(object_name, '/', 2))
    )
  );
$$;

create function private.chat_photo_cleanup_allowed(object_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select (select auth.uid())::text in (split_part(object_name, '/', 1), split_part(object_name, '/', 2))
    and exists (select 1 from private.account_photo_deletions where member_id = (select auth.uid()));
$$;

revoke all on function private.lock_chat_photo_accounts(uuid, uuid),
  private.chat_photo_upload_allowed(text), private.chat_photo_read_allowed(text),
  private.chat_photo_cleanup_allowed(text) from public, anon, authenticated;
grant execute on function private.chat_photo_upload_allowed(text), private.chat_photo_read_allowed(text),
  private.chat_photo_cleanup_allowed(text) to authenticated;

create policy chat_photo_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'chat-photos' and private.chat_photo_upload_allowed(name)
);
create policy chat_photo_read on storage.objects for select to authenticated using (
  bucket_id = 'chat-photos' and (
    (storage.allow_any_operation(array['object.get_authenticated', 'object.get_authenticated_info'])
      and private.chat_photo_read_allowed(name))
    or (storage.allow_any_operation(array['object.delete', 'object.delete_many'])
      and private.chat_photo_cleanup_allowed(name))
  )
);
create policy chat_photo_cleanup on storage.objects for delete to authenticated using (
  bucket_id = 'chat-photos' and private.chat_photo_cleanup_allowed(name)
);

create function public.send_chat_photo(message_id uuid, peer_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  object_name text;
  saved public.messages;
begin
  if actor is null or peer_id is null or message_id is null then
    raise exception 'A message and recipient are required' using errcode = '22023';
  end if;
  object_name := actor::text || '/' || peer_id::text || '/' || message_id::text || '.jpg';
  if not private.chat_photo_upload_allowed(object_name) then
    raise exception 'Messaging is unavailable' using errcode = '42501';
  end if;
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'chat-photos' and o.name = object_name and o.owner_id = actor::text
      and o.metadata->>'mimetype' = 'image/jpeg'
      and (o.metadata->>'size')::bigint between 1 and 2097152
  ) then
    raise exception 'The photo upload is incomplete' using errcode = '22023';
  end if;
  insert into public.messages(id, sender_id, recipient_id, body, photo_path)
    values (message_id, actor, peer_id, 'Photo', object_name)
    on conflict (id) do nothing;
  select * into saved from public.messages where id = message_id;
  if not found or saved.photo_path is distinct from object_name then
    raise exception 'The message already has different content' using errcode = '22023';
  end if;
end;
$$;

create function public.begin_account_photo_cleanup() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  paths jsonb;
begin
  if actor is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  perform private.lock_chat_photo_accounts(actor, actor);
  insert into private.account_photo_deletions(member_id) values (actor) on conflict do nothing;
  select coalesce(jsonb_agg(o.name order by o.name), '[]'::jsonb) into paths from (
    select name from storage.objects where bucket_id = 'chat-photos'
      and actor::text in (split_part(name, '/', 1), split_part(name, '/', 2))
    order by name limit 100
  ) o;
  return paths;
end;
$$;

create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
declare
  member uuid := auth.uid();
begin
  if member is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  perform private.lock_chat_photo_accounts(member, member);
  if exists (
    select 1 from storage.objects where bucket_id = 'chat-photos'
      and member::text in (split_part(name, '/', 1), split_part(name, '/', 2))
  ) then
    raise exception 'Photo cleanup is incomplete' using errcode = '22023';
  end if;
  delete from auth.users where id = member;
end;
$$;

revoke all on function public.send_chat_photo(uuid, uuid),
  public.begin_account_photo_cleanup(), public.delete_my_account() from public, anon, authenticated;
grant execute on function public.send_chat_photo(uuid, uuid),
  public.begin_account_photo_cleanup(), public.delete_my_account() to authenticated;
