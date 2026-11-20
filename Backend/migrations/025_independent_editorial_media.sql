-- Older clients continue to use the existing avatar field.
alter table public.profiles add column editorial_portrait text unique;

do $$
declare
  changed integer;
begin
  update public.profiles p set editorial_portrait = a.portrait
  from auth.users u join (values
    ('wardrobe', 'editor-wardrobe-portrait-v2'),
    ('camera', 'editor-camera-portrait-v2'),
    ('meetups', 'editor-meetups-portrait-v2'),
    ('etiquette', 'editor-etiquette-portrait-v2'),
    ('swatches', 'editor-swatches-portrait-v2'),
    ('scouting', 'editor-scouting-portrait-v2'),
    ('cues', 'editor-cues-portrait-v2'),
    ('map', 'editor-map-portrait-v2')
  ) a(desk, portrait) on u.raw_app_meta_data->>'sese_editorial_desk' = a.desk
  where p.id = u.id;
  get diagnostics changed = row_count;
  if changed <> 8 then raise exception 'Expected eight existing editorial profiles'; end if;

  with additions(id, previous_clip, title, description, credit, source_url, position) as (values
    ('plaza-pose', 'costume-meetup-hug', 'A pose in the plaza', 'A pink-haired performer shifts between poses in the open plaza at Anime Los Angeles.', 'AccessAccess · CC BY 3.0', 'https://commons.wikimedia.org/wiki/File:Anime_Los_Angeles_2023_-_Danganronpa_Cosplay_Gathering_(Friday).webm', 240),
    ('comiket-photo-call', 'ask-before-you-snap', 'Inside a Comiket photo call', 'A performer holds a pose while photographers frame their shots outside Comiket 105.', 'Benlisquare · CC BY-SA 4.0', 'https://commons.wikimedia.org/wiki/File:Cosplay_photography_at_Comiket_105.webm', 250),
    ('gamescom-costume-walk', 'fox-costume-in-motion', 'A walk through Gamescom', 'Costumed visitors pause for the camera in the exhibition hall at Gamescom 2023.', 'REZATA · CC BY 3.0', 'https://commons.wikimedia.org/wiki/File:Gamescom_2023_-_Cosplay_Music_Video_-_Short_Cut_Version_-_4K.webm', 260),
    ('pyrkon-parade', 'narcon-conga-line', 'Pyrkon parade colors', 'Costumed participants pass the crowd outside the exhibition halls at Pyrkon.', 'Rose Abrams · CC BY 4.0', 'https://commons.wikimedia.org/wiki/File:Pyrkon_2026_furry_parade.webm', 270)
  ), media as (
    select 'https://ujclifehtfrxtrijlaia.supabase.co/storage/v1/object/public/editorial/shorts/v1/' as base
  )
  insert into public.catalog(id, kind, publisher_id, title, description, credit, source_url, image_url, media_url, position)
  select a.id, 'Cosplay Video', c.publisher_id, a.title, a.description, a.credit, a.source_url,
    media.base || a.id || '.jpg', media.base || a.id || '.mp4', a.position
  from additions a join public.catalog c on c.id = a.previous_clip
  join auth.users u on u.id = c.publisher_id and u.raw_app_meta_data->>'sese_channel' = c.id
  cross join media;
  get diagnostics changed = row_count;
  if changed <> 4 then raise exception 'Expected four existing community publishers'; end if;
end;
$$;
notify pgrst, 'reload schema';
