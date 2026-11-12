create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text not null default 'City Resident' check (char_length(trim(display_name)) between 1 and 30),
  bio text not null default '' check (char_length(bio) <= 160),
  avatar text check (avatar in ('expo-duo', 'fan-duo')),
  discoverable boolean not null default false
);

create table public.consents (
  member_id uuid primary key references auth.users on delete cascade,
  revision text not null check (char_length(revision) between 1 and 160),
  accepted_at timestamptz not null default now()
);

create table public.catalog (
  id text primary key,
  kind text not null check (kind in ('Film Clip', 'Cosplay Video', 'District', 'Cosplay Look')),
  title text not null,
  description text not null,
  credit text not null,
  source_url text not null check (source_url like 'https://%'),
  image_url text check (image_url like 'https://%'),
  media_url text check (media_url like 'https://%'),
  position integer not null unique
);

create table public.reactions (
  member_id uuid not null default auth.uid() references public.profiles on delete cascade,
  catalog_id text not null references public.catalog on delete cascade,
  kind text not null check (kind in ('like', 'save')),
  primary key (member_id, catalog_id, kind)
);
create index reactions_catalog_idx on public.reactions(catalog_id);

create table public.follows (
  follower_id uuid not null default auth.uid() references public.profiles on delete cascade,
  target_id uuid not null references public.profiles on delete cascade,
  primary key (follower_id, target_id),
  check (follower_id <> target_id)
);
create index follows_target_idx on public.follows(target_id, follower_id);

create table public.blocks (
  blocker_id uuid not null default auth.uid() references public.profiles on delete cascade,
  target_id uuid not null references public.profiles on delete cascade,
  primary key (blocker_id, target_id),
  check (blocker_id <> target_id)
);
create index blocks_target_idx on public.blocks(target_id, blocker_id);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null default auth.uid() references public.profiles on delete cascade,
  catalog_id text not null references public.catalog on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 200),
  created_at timestamptz not null default now()
);
create index comments_catalog_created_idx on public.comments(catalog_id, created_at desc);

create table public.messages (
  id uuid primary key,
  sender_id uuid not null default auth.uid() references public.profiles on delete cascade,
  recipient_id uuid not null references public.profiles on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  check (sender_id <> recipient_id)
);
create index messages_sender_thread_idx on public.messages(sender_id, recipient_id, created_at desc);
create index messages_recipient_thread_idx on public.messages(recipient_id, sender_id, created_at desc);

create table public.inbox_preferences (
  member_id uuid not null default auth.uid() references public.profiles on delete cascade,
  peer_id uuid not null references public.profiles on delete cascade,
  pinned boolean not null default false,
  muted boolean not null default false,
  archived boolean not null default false,
  last_read_at timestamptz,
  primary key (member_id, peer_id),
  check (member_id <> peer_id)
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null default auth.uid() references public.profiles on delete cascade,
  reported_id uuid references public.profiles on delete cascade,
  catalog_id text references public.catalog on delete cascade,
  comment_id uuid references public.comments on delete cascade,
  message_id uuid references public.messages on delete cascade,
  reason text not null check (reason in ('Harassment', 'Spam', 'Inappropriate content', 'Other')),
  created_at timestamptz not null default now(),
  check (num_nonnulls(reported_id, catalog_id, comment_id, message_id) = 1),
  check (reported_id is distinct from reporter_id)
);
create index reports_reporter_created_idx on public.reports(reporter_id, created_at desc);

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create function private.is_blocked(peer uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists(select 1 from public.blocks
    where (blocker_id = (select auth.uid()) and target_id = peer)
       or (target_id = (select auth.uid()) and blocker_id = peer));
$$;
revoke all on function private.is_blocked(uuid) from public;
grant execute on function private.is_blocked(uuid) to authenticated;

create function private.can_message(peer uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select not private.is_blocked(peer)
    and exists(select 1 from public.follows where follower_id = (select auth.uid()) and target_id = peer)
    and exists(select 1 from public.follows where follower_id = peer and target_id = (select auth.uid()));
$$;
revoke all on function private.can_message(uuid) from public;
grant execute on function private.can_message(uuid) to authenticated;

create function public.bootstrap(agreement_revision text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare member uuid := auth.uid();
begin
  if member is null or agreement_revision is null or char_length(agreement_revision) not between 1 and 160 then
    raise exception 'Invalid account or agreement revision';
  end if;
  insert into public.profiles(id) values (member) on conflict do nothing;
  insert into public.consents(member_id, revision) values (member, agreement_revision)
    on conflict (member_id) do update set revision = excluded.revision, accepted_at = now()
    where consents.revision is distinct from excluded.revision;
  return jsonb_build_object('code', 0, 'message', 'ok', 'data', '{}'::jsonb);
end;
$$;
revoke all on function public.bootstrap(text) from public, anon, authenticated;
grant execute on function public.bootstrap(text) to authenticated;

create function public.delete_my_account() returns void
language plpgsql security definer set search_path = ''
as $$
declare member uuid := auth.uid();
begin
  if member is null then raise exception 'Sign in first'; end if;
  delete from auth.users where id = member;
end;
$$;
revoke all on function public.delete_my_account() from public, anon, authenticated;
grant execute on function public.delete_my_account() to authenticated;

create function public.member_counts(member uuid) returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'followers', (select count(*) from public.follows where target_id = member),
    'following', (select count(*) from public.follows where follower_id = member),
    'friends', (select count(*) from public.follows a join public.follows b
      on a.target_id = b.follower_id and a.follower_id = b.target_id where a.follower_id = member)
  ) where (select auth.uid()) is not null and not private.is_blocked(member)
    and exists (select 1 from public.profiles where id = member and (discoverable or id = (select auth.uid())));
$$;
revoke all on function public.member_counts(uuid) from public, anon, authenticated;
grant execute on function public.member_counts(uuid) to authenticated;

create function public.inbox() returns table (
  peer_id uuid, display_name text, avatar text, body text, created_at timestamptz,
  pinned boolean, muted boolean, archived boolean, unread boolean
)
language sql stable security invoker set search_path = ''
as $$
  with exchanges as (
    select recipient_id peer, m.body, m.created_at, false incoming, m.id
    from public.messages m where sender_id = (select auth.uid())
    union all
    select sender_id, m.body, m.created_at, true, m.id
    from public.messages m where recipient_id = (select auth.uid())
  ), latest as (
    select distinct on (peer) * from exchanges order by peer, created_at desc, id desc
  )
  select latest.peer, coalesce(p.display_name, 'City Resident'), p.avatar, latest.body, latest.created_at,
    coalesce(pref.pinned, false), coalesce(pref.muted, false), coalesce(pref.archived, false),
    exists(select 1 from exchanges e where e.peer = latest.peer and e.incoming
      and e.created_at > coalesce(pref.last_read_at, '-infinity'::timestamptz))
  from latest
  left join public.profiles p on p.id = latest.peer
  left join public.inbox_preferences pref on pref.peer_id = latest.peer and pref.member_id = (select auth.uid())
  order by coalesce(pref.pinned, false) desc, latest.created_at desc
  limit 100;
$$;
revoke all on function public.inbox() from public, anon, authenticated;
grant execute on function public.inbox() to authenticated;

alter table public.profiles enable row level security;
alter table public.consents enable row level security;
alter table public.catalog enable row level security;
alter table public.reactions enable row level security;
alter table public.follows enable row level security;
alter table public.blocks enable row level security;
alter table public.comments enable row level security;
alter table public.messages enable row level security;
alter table public.inbox_preferences enable row level security;
alter table public.reports enable row level security;

revoke all on public.profiles, public.consents, public.catalog, public.reactions, public.follows,
  public.blocks, public.comments, public.messages, public.inbox_preferences, public.reports
  from public, anon, authenticated;
grant select on public.profiles, public.catalog, public.reactions, public.follows, public.blocks,
  public.comments, public.messages, public.inbox_preferences to authenticated;
grant update (display_name, bio, avatar, discoverable) on public.profiles to authenticated;
grant insert (catalog_id, kind), delete on public.reactions to authenticated;
grant insert (target_id), delete on public.follows, public.blocks to authenticated;
grant insert (catalog_id, body), delete on public.comments to authenticated;
grant insert (id, recipient_id, body) on public.messages to authenticated;
grant insert (member_id, peer_id, pinned, muted, archived, last_read_at),
  update (member_id, peer_id, pinned, muted, archived, last_read_at) on public.inbox_preferences to authenticated;
grant insert (reported_id, catalog_id, comment_id, message_id, reason) on public.reports to authenticated;

create policy profile_read on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (discoverable and not private.is_blocked(id)));
create policy profile_edit on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy catalog_read on public.catalog for select to authenticated using (true);
create policy reaction_owner on public.reactions for all to authenticated
  using (member_id = (select auth.uid())) with check (member_id = (select auth.uid()));
create policy follows_read on public.follows for select to authenticated
  using ((select auth.uid()) in (follower_id, target_id) and not private.is_blocked(
    case when follower_id = (select auth.uid()) then target_id else follower_id end));
create policy follows_add on public.follows for insert to authenticated
  with check (follower_id = (select auth.uid()) and not private.is_blocked(target_id)
    and exists (select 1 from public.profiles p where p.id = target_id and p.discoverable));
create policy follows_remove on public.follows for delete to authenticated using (follower_id = (select auth.uid()));
create policy blocks_owner on public.blocks for all to authenticated
  using (blocker_id = (select auth.uid())) with check (blocker_id = (select auth.uid()));
create policy comments_read on public.comments for select to authenticated using (not private.is_blocked(author_id));
create policy comments_add on public.comments for insert to authenticated with check (author_id = (select auth.uid()));
create policy comments_remove on public.comments for delete to authenticated using (author_id = (select auth.uid()));
create policy messages_read on public.messages for select to authenticated
  using ((select auth.uid()) in (sender_id, recipient_id) and not private.is_blocked(
    case when sender_id = (select auth.uid()) then recipient_id else sender_id end));
create policy messages_send on public.messages for insert to authenticated
  with check (sender_id = (select auth.uid()) and private.can_message(recipient_id));
create policy preferences_owner on public.inbox_preferences for all to authenticated
  using (member_id = (select auth.uid())) with check (member_id = (select auth.uid()));
create policy reports_add on public.reports for insert to authenticated
  with check (reporter_id = (select auth.uid()) and
    (message_id is null or exists (select 1 from public.messages m where m.id = message_id)) and
    (comment_id is null or exists (select 1 from public.comments c where c.id = comment_id)));

alter publication supabase_realtime add table public.messages;
insert into storage.buckets (id, name, public, allowed_mime_types, file_size_limit)
values ('editorial', 'editorial', true, array['image/jpeg','image/png','video/mp4'], 52428800),
       ('agreements', 'agreements', true, array['application/pdf'], 1048576);
