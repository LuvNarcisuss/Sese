-- Publisher IDs are assigned only to verified existing members. Editorial source credits are unchanged.
alter table public.catalog add column publisher_id uuid references public.profiles on delete set null;
create index catalog_publisher_idx on public.catalog (publisher_id) where publisher_id is not null;
alter policy catalog_read on public.catalog using (publisher_id is null or not private.is_blocked(publisher_id));

create table private.short_editorial_baselines (
  catalog_id text primary key references public.catalog on delete cascade,
  likes integer not null check (likes between 20 and 50),
  saves integer not null check (saves between 20 and 50),
  shares integer not null check (shares between 20 and 50)
);
revoke all on private.short_editorial_baselines from public, anon, authenticated;
insert into private.short_editorial_baselines (catalog_id, likes, saves, shares)
select c.id, sample.likes, sample.saves, sample.shares
from (values ('fox-costume-in-motion', 43, 36, 22), ('narcon-conga-line', 37, 23, 30),
             ('costume-meetup-hug', 48, 28, 26), ('ask-before-you-snap', 34, 39, 24))
  as sample(id, likes, saves, shares)
join public.catalog c on c.id = sample.id;

create table private.short_share_events (
  member_id uuid not null references public.profiles on delete cascade,
  event_id uuid not null,
  catalog_id text not null references public.catalog on delete cascade,
  primary key (member_id, event_id)
);
create index short_share_events_catalog_idx on private.short_share_events (catalog_id);
revoke all on private.short_share_events from public, anon, authenticated;

create function private.short_counts(items text[])
returns table (catalog_id text, likes bigint, comments bigint, saves bigint, shares bigint, editorial_baseline boolean)
language sql stable security definer set search_path = '' as $$
  select c.id,
    r.likes + coalesce(b.likes, 0),
    (select count(*) from public.comments x where x.catalog_id = c.id and not private.is_blocked(x.author_id)),
    r.saves + coalesce(b.saves, 0),
    (select count(*) from private.short_share_events s where s.catalog_id = c.id) + coalesce(b.shares, 0),
    b.catalog_id is not null
  from public.catalog c
  left join private.short_editorial_baselines b on b.catalog_id = c.id and c.publisher_id is null
  cross join lateral (
    select count(*) filter (where kind = 'like') as likes, count(*) filter (where kind = 'save') as saves
    from public.reactions reaction where reaction.catalog_id = c.id
  ) r
  where (select auth.uid()) is not null and cardinality(items) <= 100 and c.id = any(items)
    and c.kind in ('Film Clip', 'Cosplay Video') and c.media_url is not null
    and (c.publisher_id is null or not private.is_blocked(c.publisher_id));
$$;

create function public.short_counts(items text[])
returns table (catalog_id text, likes bigint, comments bigint, saves bigint, shares bigint, editorial_baseline boolean)
language sql stable set search_path = '' as $$
  select * from private.short_counts(items);
$$;

create function private.record_short_share(item text, event uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
begin
  if actor is null or event is null or not exists (
    select 1 from public.catalog c where c.id = item and c.kind in ('Film Clip', 'Cosplay Video')
      and c.media_url is not null and (c.publisher_id is null or not private.is_blocked(c.publisher_id))
  ) then
    raise exception 'Short is unavailable';
  end if;
  insert into private.short_share_events (member_id, event_id, catalog_id) values (actor, event, item)
    on conflict (member_id, event_id) do nothing;
end;
$$;

create function public.record_short_share(item text, event uuid) returns void
language sql set search_path = '' as $$
  select private.record_short_share(item, event);
$$;

revoke all on function private.short_counts(text[]), public.short_counts(text[]),
  private.record_short_share(text, uuid), public.record_short_share(text, uuid) from public, anon, authenticated;
grant execute on function private.short_counts(text[]), public.short_counts(text[]),
  private.record_short_share(text, uuid), public.record_short_share(text, uuid) to authenticated;

create table public.work_reactions (
  member_id uuid not null default auth.uid() references public.profiles on delete cascade,
  work_id uuid not null references public.works on delete cascade,
  kind text not null check (kind in ('like', 'save')),
  primary key (member_id, work_id, kind)
);
create index work_reactions_work_idx on public.work_reactions (work_id, kind);
alter table public.work_reactions enable row level security;
revoke all on public.work_reactions from public, anon, authenticated;
grant select, delete on public.work_reactions to authenticated;
grant insert (work_id, kind) on public.work_reactions to authenticated;
create policy work_reactions_read on public.work_reactions for select to authenticated
  using (member_id = (select auth.uid()));
create policy work_reactions_add on public.work_reactions for insert to authenticated
  with check (member_id = (select auth.uid()) and exists (
    select 1 from public.works w where w.id = work_id and w.status = 'approved'
  ));
create policy work_reactions_remove on public.work_reactions for delete to authenticated
  using (member_id = (select auth.uid()));

create table public.cosplay_video_reactions (
  member_id uuid not null default auth.uid() references public.profiles on delete cascade,
  post_id uuid not null references public.cosplay_posts on delete cascade,
  kind text not null check (kind in ('like', 'save')),
  primary key (member_id, post_id, kind)
);
create index cosplay_video_reactions_post_idx on public.cosplay_video_reactions (post_id, kind);
alter table public.cosplay_video_reactions enable row level security;
revoke all on public.cosplay_video_reactions from public, anon, authenticated;
grant select, delete on public.cosplay_video_reactions to authenticated;
grant insert (post_id, kind) on public.cosplay_video_reactions to authenticated;
create policy cosplay_video_reactions_read on public.cosplay_video_reactions for select to authenticated
  using (member_id = (select auth.uid()));
create policy cosplay_video_reactions_add on public.cosplay_video_reactions for insert to authenticated
  with check (member_id = (select auth.uid()) and exists (
    select 1 from public.cosplay_posts p where p.id = post_id and p.media_kind = 'video' and p.status = 'approved'
  ));
create policy cosplay_video_reactions_remove on public.cosplay_video_reactions for delete to authenticated
  using (member_id = (select auth.uid()));

create function private.publication_counts(item uuid, source text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('likes', count(*) filter (where kind = 'like'), 'saves', count(*) filter (where kind = 'save'))
  from (
    select r.kind from public.work_reactions r join public.works w on w.id = r.work_id
    join public.profiles p on p.id = w.owner_id
    where source = 'work' and w.id = item and w.status = 'approved' and (p.discoverable or p.id = (select auth.uid()))
      and not private.is_blocked(p.id)
    union all
    select r.kind from public.cosplay_video_reactions r join public.cosplay_posts w on w.id = r.post_id
    join public.profiles p on p.id = w.owner_id
    where source = 'cosplay' and w.id = item and w.media_kind = 'video' and w.status = 'approved'
      and (p.discoverable or p.id = (select auth.uid())) and not private.is_blocked(p.id)
  ) reactions
  having (select auth.uid()) is not null;
$$;
create function public.publication_counts(item uuid, source text) returns jsonb
language sql stable set search_path = '' as $$
  select private.publication_counts(item, source);
$$;
revoke all on function private.publication_counts(uuid, text), public.publication_counts(uuid, text) from public, anon, authenticated;
grant execute on function private.publication_counts(uuid, text), public.publication_counts(uuid, text) to authenticated;

-- Tighten interactions for catalog items assigned to a blocked publisher without preventing removal of old saves.
alter policy reaction_owner on public.reactions with check (
  member_id = (select auth.uid()) and exists (select 1 from public.catalog c where c.id = catalog_id)
);
alter policy comments_read on public.comments using (
  not private.is_blocked(author_id) and exists (select 1 from public.catalog c where c.id = catalog_id)
);
alter policy comments_add on public.comments with check (
  author_id = (select auth.uid()) and exists (select 1 from public.catalog c where c.id = catalog_id)
);

create or replace function public.member_counts(member uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'followers', (select count(*) from public.follows where target_id = member),
    'following', (select count(*) from public.follows where follower_id = member),
    'friends', (select count(*) from public.follows a join public.follows b
      on a.target_id = b.follower_id and a.follower_id = b.target_id where a.follower_id = member),
    'likes', totals.likes,
    'saves', totals.saves
  )
  from lateral (
    select count(*) filter (where kind = 'like') as likes, count(*) filter (where kind = 'save') as saves
    from (
      select r.kind from public.reactions r join public.catalog c on c.id = r.catalog_id
      where c.publisher_id = member and c.kind in ('Film Clip', 'Cosplay Video') and c.media_url is not null
      union all
      select r.kind from public.work_reactions r join public.works w on w.id = r.work_id
      where w.owner_id = member and w.status = 'approved'
      union all
      select r.kind from public.cosplay_video_reactions r join public.cosplay_posts p on p.id = r.post_id
      where p.owner_id = member and p.media_kind = 'video' and p.status = 'approved'
    ) reactions
  ) totals
  where (select auth.uid()) is not null and not private.is_blocked(member)
    and exists (select 1 from public.profiles where id = member and (discoverable or id = (select auth.uid())));
$$;

notify pgrst, 'reload schema';
