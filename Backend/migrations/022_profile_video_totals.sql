-- Each editorial baseline belongs to one video, independent of its number of reactions.
create or replace function public.member_counts(member uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  with published_shorts as (
    select id from public.catalog
    where publisher_id = member and kind in ('Film Clip', 'Cosplay Video') and media_url is not null
  ), editorial as (
    select coalesce(sum(b.likes), 0) as likes, coalesce(sum(b.saves), 0) as saves
    from private.short_editorial_baselines b join published_shorts s on s.id = b.catalog_id
  ), received as (
    select r.kind from public.reactions r join published_shorts s on s.id = r.catalog_id
    union all
    select r.kind from public.work_reactions r join public.works w on w.id = r.work_id
    where w.owner_id = member and w.status = 'approved'
    union all
    select r.kind from public.cosplay_video_reactions r join public.cosplay_posts p on p.id = r.post_id
    where p.owner_id = member and p.media_kind = 'video' and p.status = 'approved'
  ), interactions as (
    select count(*) filter (where kind = 'like') as likes, count(*) filter (where kind = 'save') as saves
    from received
  )
  select jsonb_build_object(
    'followers', (select count(*) from public.follows where target_id = member),
    'following', (select count(*) from public.follows where follower_id = member),
    'friends', (select count(*) from public.follows a join public.follows b
      on a.target_id = b.follower_id and a.follower_id = b.target_id where a.follower_id = member),
    'likes', editorial.likes + interactions.likes,
    'saves', editorial.saves + interactions.saves
  )
  from editorial cross join interactions
  where (select auth.uid()) is not null and not private.is_blocked(member)
    and exists (select 1 from public.profiles where id = member and (discoverable or id = (select auth.uid())));
$$;
