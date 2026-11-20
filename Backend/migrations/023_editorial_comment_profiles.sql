-- Credit the existing prepared discussions to four sign-in-disabled editorial desks.
-- The immutable editorial keys distinguish them from member submissions.
alter table public.comments drop constraint comments_author_kind;

do $$
declare
  desk record;
  editor uuid;
begin
  for desk in select * from (values
    ('wardrobe', 'Hem & Thread · Editor', 'expo-judy', 'The Sese editorial desk for costume construction, styling and character details.'),
    ('camera', 'Frame Finder · Editor', 'expo-nick', 'The Sese editorial desk for filming, framing and cosplay photography.'),
    ('meetups', 'Parade Post · Editor', 'fan-duo', 'The Sese editorial desk for convention meetups, movement and performances.'),
    ('etiquette', 'Con Compass · Editor', 'expo-duo', 'The Sese editorial desk for consent, accessibility and convention etiquette.')
  ) desks(slug, nickname, portrait, bio)
  loop
    insert into auth.users(id, raw_app_meta_data, banned_until, created_at, updated_at)
      values (gen_random_uuid(), jsonb_build_object('sese_editorial_desk', desk.slug),
              '9999-12-31 00:00:00+00', now(), now()) returning id into editor;
    insert into public.profiles(id, display_name, avatar, discoverable, bio)
      values (editor, desk.nickname, desk.portrait, true, desk.bio);

    -- Numbers refer to the stable discussion keys from migration 017, independent of feed order.
    with assignments(clip, topic, entries) as (values
      ('fox-costume-in-motion','wardrobe',array[1,2,4,5,6,7,8,9,11,12,14,15,17,19,20,21,24]),
      ('fox-costume-in-motion','camera',array[3,10,16,18,22,23]),
      ('fox-costume-in-motion','etiquette',array[13]),
      ('narcon-conga-line','meetups',array[1,2,4,9,10,11,12,16,18,20,21]),
      ('narcon-conga-line','wardrobe',array[3,5,7,13,22]),
      ('narcon-conga-line','camera',array[6,14]),
      ('narcon-conga-line','etiquette',array[8,15,17,19]),
      ('costume-meetup-hug','meetups',array[1,5,7,11,12,14,20,21,25]),
      ('costume-meetup-hug','etiquette',array[2,3,8,9,10,13,17,19,22,23,26]),
      ('costume-meetup-hug','wardrobe',array[4,6,15,18,24]),
      ('costume-meetup-hug','camera',array[16]),
      ('ask-before-you-snap','etiquette',array[1,2,5,6,7,8,10,11,12,13,14,20,21]),
      ('ask-before-you-snap','camera',array[3,4,9,16,17,18,19]),
      ('ask-before-you-snap','wardrobe',array[15])
    )
    update public.comments c set author_id = editor
    from assignments a cross join lateral unnest(a.entries) n
    where a.topic = desk.slug and c.catalog_id = a.clip and c.author_id is null
      and c.editorial_key = a.clip || ':discussion:' || lpad(n::text, 2, '0');
  end loop;
end;
$$;

alter table public.comments alter column author_id set not null;
alter table public.comments add constraint comments_editorial_key_length
  check (editorial_key is null or char_length(editorial_key) between 1 and 100);
notify pgrst, 'reload schema';
