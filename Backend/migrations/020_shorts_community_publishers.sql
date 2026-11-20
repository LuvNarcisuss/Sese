-- Assign the four licensed clips to app-managed community publishers.
-- Copyright attribution stays on each catalog item. No sign-in identity is issued.
do $$
declare
  channel record;
  publisher uuid;
begin
  for channel in
    select * from (values
      ('ask-before-you-snap', 'Convention Notebook', 'expo-duo'),
      ('costume-meetup-hug', 'Meetup Lens', 'expo-nick'),
      ('fox-costume-in-motion', 'Fox Wardrobe', 'expo-judy'),
      ('narcon-conga-line', 'Parade Diary', 'fan-duo')
    ) as channels(clip, name, portrait)
  loop
    select publisher_id into strict publisher from public.catalog where id = channel.clip for update;
    if publisher is not null then
      if exists (select 1 from auth.users u where u.id = publisher
        and u.raw_app_meta_data ->> 'sese_channel' = channel.clip) then
        continue;
      end if;
      raise exception 'Clip % already has a publisher', channel.clip;
    end if;
    insert into auth.users(id, raw_app_meta_data, banned_until, created_at, updated_at)
      values (gen_random_uuid(), jsonb_build_object('sese_channel', channel.clip),
              '9999-12-31 00:00:00+00', now(), now())
      returning id into publisher;
    insert into public.profiles(id, display_name, avatar, discoverable, bio)
      values (publisher, channel.name, channel.portrait, true, 'A Sese community channel sharing licensed costume films.');
    update public.catalog set publisher_id = publisher where id = channel.clip;
  end loop;
end;
$$;

-- A clip retains its labeled editorial estimates when a publisher is assigned.
create or replace function private.short_counts(items text[])
returns table (catalog_id text, likes bigint, comments bigint, saves bigint, shares bigint, editorial_baseline boolean)
language sql stable security definer set search_path = '' as $$
  select c.id,
    r.likes + coalesce(b.likes, 0),
    (select count(*) from public.comments x where x.catalog_id = c.id and not private.is_blocked(x.author_id)),
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
