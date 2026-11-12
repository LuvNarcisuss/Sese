update public.catalog as item
set image_url = 'https://ujclifehtfrxtrijlaia.supabase.co/storage/v1/object/public/editorial/' || image.object_name
from (values
  ('district-sahara', 'sese-media-v1/district-sahara.png'),
  ('district-tundra', 'sese-media-v1/district-tundra.png'),
  ('district-rainforest', 'sese-media-v1/district-rainforest.png'),
  ('expo-duo', '944f77db-dbc1-4293-976a-e6bc0dc71f39/expo-duo.jpg'),
  ('fan-duo', 'sese-media-v1/fan-duo.jpg')
) as image(id, object_name)
where item.id = image.id;
