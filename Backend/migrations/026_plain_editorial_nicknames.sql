-- Update only the eight managed discussion profiles and their displayed block-list labels.
with renamed as (
  update public.profiles p
  set display_name = regexp_replace(p.display_name, ' · Editor$', ''), bio = ''
  from auth.users u
  where p.id = u.id and u.raw_app_meta_data->>'sese_editorial_desk' in
    ('wardrobe', 'camera', 'meetups', 'etiquette', 'swatches', 'scouting', 'cues', 'map')
    and (p.display_name like '% · Editor' or p.bio <> '')
  returning p.id, p.display_name
)
update public.blocks b set label = r.display_name
from renamed r
where b.target_id = r.id and b.label = r.display_name || ' · Editor';
