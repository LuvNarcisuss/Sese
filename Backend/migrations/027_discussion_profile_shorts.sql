-- Allow a Short to have like and save estimates without a share estimate.
alter table private.short_editorial_baselines
  drop constraint short_editorial_baselines_shares_check,
  add constraint short_editorial_baselines_shares_check check (shares = 0 or shares between 20 and 50);

do $$
declare
  added integer;
  media constant text := 'https://ujclifehtfrxtrijlaia.supabase.co/storage/v1/object/public/editorial/shorts/v1/';
begin
  with clips(id, desk, title, description, credit, source_url, position) as (values
    ('gamescom-emerald-costume', 'wardrobe', 'Emerald at Gamescom', 'A performer in a flowing green costume turns in the Gamescom exhibition hall.', 'REZATA · CC BY 3.0', 'https://commons.wikimedia.org/wiki/File:Gamescom_2022_K%C3%B6ln-Cologne_-_Cosplay_Music_Video_-_Best_Cosplays_-_4K.webm', 280),
    ('smash-photo-session', 'camera', 'Blue ribbons at SMASH', 'A blue-haired cosplayer changes poses for a photographer on the plaza at SMASH.', 'Benlisquare · CC BY-SA 4.0', 'https://commons.wikimedia.org/wiki/File:Cosplay_photography_at_SMASH_2025.webm', 290),
    ('wonder-star-staff', 'cues', 'A star at Wonder Festival', 'A performer in violet lifts a crescent staff and turns its gold star toward the camera.', 'ローアングルおじさん/COSPLAY · CC BY 3.0', 'https://commons.wikimedia.org/wiki/File:%E3%83%AF%E3%83%B3%E3%83%80%E3%83%BC%E3%83%95%E3%82%A7%E3%82%B9%E3%83%86%E3%82%A3%E3%83%90%E3%83%AB_2019_%E5%A4%8F_%E3%82%B3%E3%82%B9%E3%83%97%E3%83%AC%E3%82%A4%E3%83%A4%E3%83%BC%E2%91%A4.webm', 300)
  )
  insert into public.catalog(id, publisher_id, kind, title, description, credit, source_url, position, media_url, image_url)
  select c.id, p.id, 'Cosplay Video', c.title, c.description, c.credit, c.source_url, c.position,
    media || c.id || '.mp4', media || c.id || '.jpg'
  from clips c join auth.users u on u.raw_app_meta_data->>'sese_editorial_desk' = c.desk
  join public.profiles p on p.id = u.id and p.discoverable;
  get diagnostics added = row_count;
  if added <> 3 then raise exception 'Expected three existing public discussion profiles'; end if;

  insert into private.short_editorial_baselines(catalog_id, likes, saves, shares) values
    ('gamescom-emerald-costume', 41, 26, 0),
    ('smash-photo-session', 32, 21, 0),
    ('wonder-star-staff', 38, 29, 0);
end;
$$;
