-- All fixtures and changes to reactions are confined to this transaction.
begin;
create function pg_temp.fixture(key text) returns uuid language sql stable as
$$ select current_setting('profile_check.' || key)::uuid $$;
select set_config('profile_check.' || k, gen_random_uuid()::text, true)
from unnest(array['author','viewer','other','first','second','third','work','pending','cosplay','photo']) k;

insert into auth.users(id) select pg_temp.fixture(k) from unnest(array['author','viewer','other']) k;
insert into public.profiles(id, discoverable)
select pg_temp.fixture(k), true from unnest(array['author','viewer','other']) k;
insert into public.catalog(id, kind, title, description, credit, source_url, media_url, publisher_id, position)
select pg_temp.fixture(k)::text, 'Film Clip', 'Profile count check', '', '', 'https://example.com',
  'https://example.com/video.mp4', pg_temp.fixture('author'),
  (select coalesce(min(position), 0) from public.catalog) - ordinal::int
from unnest(array['first','second','third']) with ordinality clips(k,ordinal);
insert into private.short_editorial_baselines(catalog_id, likes, saves, shares)
values (pg_temp.fixture('first')::text,20,40,20), (pg_temp.fixture('second')::text,30,25,20);
insert into public.works(id, owner_id, title, source_url, status)
select pg_temp.fixture(k), pg_temp.fixture('author'), 'Profile count check',
  'https://www.youtube.com/watch?v=abcde123456', status
from (values ('work','approved'), ('pending','pending')) works(k,status);
insert into public.cosplay_posts(id, owner_id, title, caption, media_kind, media_path, status)
select pg_temp.fixture(k), pg_temp.fixture('author'), 'Profile count check', '', media_kind,
  pg_temp.fixture('author')::text || '/' || pg_temp.fixture(k)::text || extension, 'approved'
from (values ('cosplay','video','.mp4'), ('photo','photo','.jpg')) posts(k,media_kind,extension);

insert into public.reactions(member_id, catalog_id, kind)
select pg_temp.fixture(actor), pg_temp.fixture(clip)::text, kind
from (values ('viewer','first','like'), ('other','first','like'), ('other','third','save')) r(actor,clip,kind);
insert into public.work_reactions(member_id, work_id, kind)
select pg_temp.fixture('viewer'), pg_temp.fixture(k), kind
from (values ('work','like'), ('work','save'), ('pending','like')) r(k,kind);
insert into public.cosplay_video_reactions(member_id, post_id, kind)
select pg_temp.fixture('other'), pg_temp.fixture(k), kind
from (values ('cosplay','save'), ('photo','like')) r(k,kind);

create function pg_temp.check_totals(expected_likes int, expected_saves int) returns void language plpgsql as $$
declare profile jsonb := public.member_counts(pg_temp.fixture('author'));
  video_likes bigint;
  video_saves bigint;
begin
  with individual as (
    select likes, saves from public.short_counts(array[pg_temp.fixture('first')::text,
      pg_temp.fixture('second')::text, pg_temp.fixture('third')::text])
    union all
    select (counts->>'likes')::bigint, (counts->>'saves')::bigint
    from (values ('cosplay'),('work')) videos(source)
    cross join lateral public.publication_counts(pg_temp.fixture(source), source) counts
  )
  select sum(likes), sum(saves) into video_likes, video_saves from individual;
  if (video_likes, video_saves) is distinct from (expected_likes::bigint, expected_saves::bigint)
     or ((profile->>'likes')::bigint, (profile->>'saves')::bigint) is distinct from (video_likes, video_saves)
  then raise exception 'Profile % differs from the expected video totals (%, %)', profile, expected_likes, expected_saves; end if;
end $$;

select set_config('request.jwt.claim.sub', pg_temp.fixture('viewer')::text, true);
set local role authenticated;
select pg_temp.check_totals(53,68);
insert into public.reactions(catalog_id,kind) values (pg_temp.fixture('first')::text,'save');
delete from public.reactions where member_id = auth.uid() and catalog_id = pg_temp.fixture('first')::text and kind = 'like';
select pg_temp.check_totals(52,69);
delete from public.reactions where member_id = auth.uid() and catalog_id = pg_temp.fixture('first')::text and kind = 'save';
insert into public.reactions(catalog_id,kind) values (pg_temp.fixture('first')::text,'like');
select pg_temp.check_totals(53,68);
do $$begin
  if (public.member_counts(auth.uid()) @> '{"likes":0,"saves":0}') is distinct from true then
    raise exception 'An account without videos must have zero received reactions'; end if;
end $$;
select public.block_from_source(pg_temp.fixture('author'), null);
do $$begin
  if public.member_counts(pg_temp.fixture('author')) is not null then raise exception 'Blocked profile is visible'; end if;
end $$;
select 'Profile totals matched individual videos, reaction changes, empty profiles and block visibility' as verification;
rollback;
