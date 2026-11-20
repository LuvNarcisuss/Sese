-- Verify public profile navigation and per-account moderation without retaining any writes.
begin;
do $$
begin
  if (select count(*) from auth.users where raw_app_meta_data ? 'sese_editorial_desk') <> 8
    or exists (select from auth.users u where u.raw_app_meta_data ? 'sese_editorial_desk'
      and (u.banned_until is null or u.banned_until <= now() or exists (select from auth.identities i where i.user_id = u.id)))
  then raise exception 'Editorial account configuration is incomplete'; end if;
end $$;
select set_config('sese_check.viewer', gen_random_uuid()::text, true);
insert into auth.users(id) values (current_setting('sese_check.viewer')::uuid);
insert into public.profiles(id) values (current_setting('sese_check.viewer')::uuid);
select set_config('request.jwt.claim.sub', current_setting('sese_check.viewer'), true);
set local role authenticated;
do $$
declare
  thread text := 'costume-meetup-hug';
  entry public.comments;
  before_count int;
  desk_count int;
begin
  if (select count(*) from public.comments where editorial_key is not null) <> 93
    or (select count(distinct c.catalog_id) from public.comments c where editorial_key is not null) <> 4
    or exists (select from public.comments where editorial_key is not null group by catalog_id having count(distinct author_id) <> 8)
    or (select count(distinct p.avatar) from public.comments c join public.profiles p on p.id = c.author_id
        where c.editorial_key is not null) <> 8
    or exists (select from public.comments where editorial_key is not null
      group by catalog_id, author_id having count(*) not between 2 and 4)
    or exists (select from public.comments c left join public.profiles p on p.id = c.author_id
      where c.editorial_key is not null and (p.id is null or not p.discoverable or p.display_name ilike '% · Editor'
        or p.bio <> ''
        or public.member_counts(p.id) is null))
  then raise exception 'Editorial bylines or profile visibility mismatch'; end if;
  if has_column_privilege('authenticated', 'public.comments', 'editorial_key', 'INSERT')
    or has_column_privilege('authenticated', 'public.comments', 'author_id', 'INSERT')
  then raise exception 'Member can supply editorial attribution'; end if;
  select * into strict entry from public.comments where editorial_key = thread || ':discussion:01';
  select count(*) into before_count from public.comments where catalog_id = thread;
  select count(*) into desk_count from public.comments where catalog_id = thread and author_id = entry.author_id;
  perform public.submit_comment_report(entry.id,'Other');
  perform public.block_from_source(entry.author_id, 'comment:' || (select id from public.comments
    where catalog_id = thread and author_id = entry.author_id limit 1));
  if exists (select from public.comments where author_id = entry.author_id)
    or exists (select from public.profiles where id = entry.author_id)
    or (select comments from public.short_counts(array[thread])) is distinct from (before_count - desk_count)::bigint
  then raise exception 'Blocking the desk did not hide only its comments and profile'; end if;
  delete from public.blocks where target_id = entry.author_id;
  if exists (select from public.comments where id = entry.id)
    or (select comments from public.short_counts(array[thread])) is distinct from (before_count - 1)::bigint
  then raise exception 'Unblock did not preserve the individual report'; end if;
  perform public.withdraw_comment_report(entry.id);
  if (select comments from public.short_counts(array[thread])) is distinct from before_count::bigint
    or not exists(select from public.profiles where id = entry.author_id)
  then raise exception 'Undo did not restore the discussion and desk'; end if;
end $$;
select 'Eight distinct editorial profiles in each thread, 93 credited comments, and independent report/block verified' as verification;
rollback;
