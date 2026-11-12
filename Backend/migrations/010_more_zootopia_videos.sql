insert into public.catalog (id, kind, title, description, credit, source_url, image_url, position) values
('flash-at-the-dmv', 'Film Clip', 'Flash at the DMV',
 'Judy and Nick need a plate number from the city’s slowest clerk. Official sloth trailer.',
 'Walt Disney Animation Studios',
 'https://www.youtube.com/watch?v=bY73vFGhSVk',
 'https://i.ytimg.com/vi/bY73vFGhSVk/sddefault.jpg', 110),
('gary-at-the-gala', 'Film Clip', 'Gary at the Gala',
 'Gary makes a surprise entrance at the Zootennial Gala. Official Japanese-dubbed clip.',
 'Disney Japan',
 'https://www.disney.co.jp/movie/zootopia2/news/20251204_01',
 'https://lumiere-a.akamaihd.net/v1/images/news_zootopia2_20251204_01_9763b5f9.jpeg?region=0%2C1%2C1200%2C675&width=960', 120),
('zootopia-two-trailer', 'Film Clip', 'Zootopia 2 Official Trailer',
 'Partners in crisis, an undercover case, and a new trail through the city.',
 'Walt Disney Animation Studios',
 'https://video.disney.com/watch/zootopia-2-trailer-63b2807aa1399deb74651fcd',
 'https://i.ytimg.com/vi/BjkIOU5PhyQ/maxresdefault.jpg', 130)
on conflict (id) do nothing;
