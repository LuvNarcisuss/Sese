-- Resolve cover metadata only for the viewer's own active report history.
create function private.reported_video_history(page_offset integer)
returns table(target_key text, label text, detail text, cover_url text, preview_path text)
language sql stable security definer set search_path = '' as $$
  with page as (
    select h.target_key, h.label, h.reason, h.reported_at
    from private.video_hides h where h.actor = (select auth.uid())
    order by h.reported_at desc, h.target_key limit 100 offset greatest(page_offset, 0)
  )
  select h.target_key, h.label, h.reason,
    coalesce(c.image_url, 'https://i.ytimg.com/vi/' || split_part(w.source_url, 'v=', 2) || '/hqdefault.jpg'),
    p.media_path
  from page h
  left join public.catalog c on h.target_key = 'catalog:' || c.id
    and c.kind in ('Film Clip','Cosplay Video')
    and (c.publisher_id is null or not private.is_blocked(c.publisher_id))
  left join public.works w on w.id = substring(h.target_key from '^work:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$')::uuid
    and w.status = 'approved' and not private.is_blocked(w.owner_id)
    and exists(select 1 from public.profiles pr where pr.id=w.owner_id and pr.discoverable)
  left join public.cosplay_posts p on p.id = substring(h.target_key from '^cosplay:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$')::uuid
    and p.media_kind = 'video' and p.status = 'approved' and not private.is_blocked(p.owner_id)
    and exists(select 1 from public.profiles pr where pr.id=p.owner_id and pr.discoverable)
  order by h.reported_at desc, h.target_key;
$$;

create function public.reported_video_history(page_offset integer default 0)
returns table(target_key text, label text, detail text, cover_url text, preview_path text)
language sql stable security invoker set search_path = '' as $$
  select * from private.reported_video_history(page_offset);
$$;

revoke all on function private.reported_video_history(integer), public.reported_video_history(integer)
  from public, anon, authenticated;
grant execute on function private.reported_video_history(integer), public.reported_video_history(integer)
  to authenticated;
notify pgrst, 'reload schema';
