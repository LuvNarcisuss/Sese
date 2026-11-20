alter table public.profiles drop constraint profiles_avatar_check,
  add constraint profiles_avatar_check check (avatar in (
    'expo-duo','fan-duo','expo-judy','expo-nick','desk-fox','desk-parade','desk-meetup','desk-kodachi'
  ));

do $$
declare
  desk record;
  entry record;
  assigned uuid;
  last_editor uuid;
  last_clip text;
begin
  -- Keep any existing moderation attribution stable across the reassignment.
  lock table public.comments in share row exclusive mode;
  lock table public.blocks, public.reports in share mode;
  create temporary table discussion_roster (
    editor uuid primary key, slug text unique not null, topic text not null
  ) on commit drop;
  insert into discussion_roster select id, slug, slug from auth.users
    cross join lateral (select raw_app_meta_data->>'sese_editorial_desk' as slug) s
    where slug in ('wardrobe','camera','meetups','etiquette');
  if (select count(*) from discussion_roster) <> 4 then raise exception 'Missing original editorial desks'; end if;

  for desk in select * from (values
    ('swatches','wardrobe','Swatch Book · Editor','desk-fox','Costume colors, textures and details from the Sese editorial team.'),
    ('scouting','camera','Scene Scout · Editor','desk-meetup','Camera angles, movement and visual storytelling from the Sese editorial team.'),
    ('cues','meetups','Cue Card · Editor','desk-parade','Character gestures and convention performances from the Sese editorial team.'),
    ('map','etiquette','Meetup Map · Editor','desk-kodachi','Welcoming spaces and practical convention tips from the Sese editorial team.')
  ) d(slug,topic,nickname,portrait,bio)
  loop
    insert into auth.users(id, raw_app_meta_data, banned_until, created_at, updated_at)
      values (gen_random_uuid(),jsonb_build_object('sese_editorial_desk',desk.slug),'9999-12-31 00:00:00+00',now(),now())
      returning id into assigned;
    insert into public.profiles(id,display_name,avatar,discoverable,bio)
      values (assigned,desk.nickname,desk.portrait,true,desk.bio);
    insert into discussion_roster values (assigned,desk.slug,desk.topic);
  end loop;

  create temporary table discussion_bylines on commit drop as
    select c.id, c.catalog_id, c.created_at, c.author_id as original, r.topic,
      case when exists(select from public.blocks b where b.target_id=c.author_id)
        or exists(select from private.report_receipts h where 'comment:' || c.id in (h.target_key,h.source_key))
        or exists(select from private.block_notices b where b.comment_id=c.id)
        then c.author_id end as editor
    from public.comments c join discussion_roster r on r.editor=c.author_id
    where c.editorial_key like c.catalog_id || ':discussion:%' and c.catalog_id in
      ('fox-costume-in-motion','narcon-conga-line','costume-meetup-hug','ask-before-you-snap');

  -- Work in feed order. Balance each thread, then prefer a different consecutive byline
  -- and the original subject desk. Protected entries already count towards the allocation.
  for entry in select * from discussion_bylines order by catalog_id,created_at desc,id desc loop
    if entry.catalog_id is distinct from last_clip then last_editor := null; end if;
    assigned := entry.editor;
    if assigned is null then
      select r.editor into strict assigned from discussion_roster r
        left join discussion_bylines b on b.catalog_id=entry.catalog_id and b.editor=r.editor
        group by r.editor,r.slug,r.topic
        order by count(b.id), (r.editor is not distinct from last_editor),
          (r.topic <> entry.topic), (r.editor <> entry.original), r.slug limit 1;
      update discussion_bylines set editor=assigned where id=entry.id;
    end if;
    last_editor := assigned;
    last_clip := entry.catalog_id;
  end loop;

  update public.comments c set author_id=b.editor from discussion_bylines b
    where c.id=b.id and c.author_id is distinct from b.editor;
end;
$$;
