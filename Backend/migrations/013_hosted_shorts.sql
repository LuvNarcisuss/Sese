with shorts(id, kind, title, description, credit, source_url, position) as (
  values
  ('fox-costume-in-motion', 'Cosplay Video', 'How a fox costume moves', 'Two angles show how the tails, ears and makeup shape a fox-inspired performance.', 'TBD Tuyên · Pexels', 'https://www.pexels.com/video/enchanting-female-in-vibrant-fox-themed-costume-32542808/', 200),
  ('narcon-conga-line', 'Cosplay Video', 'Follow the conga line', 'Animal-costume dancers wind across the lawn at NärCon Sommar in this portrait cut.', 'Rose Abrams · CC BY-SA 4.0', 'https://commons.wikimedia.org/wiki/File:N%C3%A4rCon_Sommar_2025_-_conga_line_of_furries.webm', 210),
  ('costume-meetup-hug', 'Cosplay Video', 'A costume meet-up hug', 'A green animal costume steals the scene in this portrait cut of a meet-up greeting.', 'Dimitri Torterat · CC BY 2.0 France', 'https://commons.wikimedia.org/wiki/File:Diti_hugs_Natalie.ogv', 220),
  ('ask-before-you-snap', 'Film Clip', 'Ask before you snap', 'TITANIA animates a rule for convention photos in this reframed and captioned excerpt.', 'TITANIA · CC BY 3.0', 'https://commons.wikimedia.org/wiki/File:TITANIA_-_Fursuit_Etiquette_%282024%29.webm', 230)
),
storage(base_url) as (
  values ('https://ujclifehtfrxtrijlaia.supabase.co/storage/v1/object/public/editorial/shorts/v1/')
)
insert into public.catalog (id, kind, title, description, credit, source_url, image_url, media_url, position)
select id, kind, title, description, credit, source_url, base_url || id || '.jpg', base_url || id || '.mp4', position
from shorts cross join storage
on conflict (id) do update
set kind = excluded.kind,
    title = excluded.title,
    description = excluded.description,
    credit = excluded.credit,
    source_url = excluded.source_url,
    image_url = excluded.image_url,
    media_url = excluded.media_url,
    position = excluded.position
returning id, position, media_url, image_url;
