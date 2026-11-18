-- Use only in an isolated PostgreSQL database with the Sese migrations applied.
begin;
create function pg_temp.assert_true(condition boolean, description text) returns void
language plpgsql as $$begin if condition is distinct from true then raise exception '%', description; end if; end;$$;
insert into auth.users(id) values
  ('00000000-0000-4000-8000-000000000001'),('00000000-0000-4000-8000-000000000002'),
  ('00000000-0000-4000-8000-000000000003');
insert into public.profiles(id, display_name, discoverable) values
  ('00000000-0000-4000-8000-000000000001','Viewer',true),
  ('00000000-0000-4000-8000-000000000002','Maker',true),
  ('00000000-0000-4000-8000-000000000003','Private name',false);
update public.catalog set publisher_id='00000000-0000-4000-8000-000000000002' where id='narcon-conga-line';
insert into public.works(id,owner_id,title,source_url,status) values
 ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','Member movie','https://www.youtube.com/watch?v=abcde123456','approved');
insert into public.cosplay_posts(id,owner_id,title,caption,media_kind,media_path,status) values
 ('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','Cosplay clip','','video','00000000-0000-4000-8000-000000000002/20000000-0000-4000-8000-000000000001.mp4','approved');
insert into public.cosplay_posts(id,owner_id,title,caption,media_kind,media_path,status) values
 ('20000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002','Costume photo','','photo','00000000-0000-4000-8000-000000000002/20000000-0000-4000-8000-000000000002.jpg','approved');
insert into public.comments(id,author_id,catalog_id,body) values
 ('30000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','ask-before-you-snap','Comment from a private member');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000001';
do $$declare nonvideo text; begin
  select id into strict nonvideo from public.catalog where kind='District' limit 1;
  begin
    perform public.submit_video_report('catalog',nonvideo,'Spam');
    raise exception 'Unexpected successful non-video catalog report' using errcode='23514';
  exception when raise_exception then null;
  end;
  begin
    perform public.submit_video_report('cosplay','20000000-0000-4000-8000-000000000002','Spam');
    raise exception 'Unexpected successful photo report on video RPC' using errcode='23514';
  exception when raise_exception then null;
  end;
end$$;
select pg_temp.assert_true(count(*)=0,'Bad targets never enter video history') from public.safety_history('report',0);
select public.submit_video_report('catalog','narcon-conga-line','Harassment');
select public.submit_video_report('catalog','narcon-conga-line','Harassment');
select public.submit_video_report('work','10000000-0000-4000-8000-000000000001','Spam');
select public.submit_video_report('cosplay','20000000-0000-4000-8000-000000000001','Other');
select pg_temp.assert_true(count(*)=3,'Report history deduplicates by viewer and target') from public.safety_history('report',0);
select pg_temp.assert_true(count(*)=1,'Hidden catalog title stays identifiable') from public.safety_history('report',0) where label='Follow the conga line';
select pg_temp.assert_true(count(*)=0,'Reported catalog video is hidden') from public.catalog where id='narcon-conga-line';
select pg_temp.assert_true(count(*)=0,'Reported work is hidden') from public.works where title='Member movie';
select pg_temp.assert_true(count(*)=0,'Reported cosplay post is hidden') from public.cosplay_posts where title='Cosplay clip';
select pg_temp.assert_true(count(*)=3 and count(cover_url)=2 and count(preview_path)=1,
  'Only the three reported videos provide eligible cover metadata') from public.reported_video_history(0);
select public.block_member('00000000-0000-4000-8000-000000000002');
select pg_temp.assert_true(count(*)=1,'Blocked display name survives profile filtering') from public.safety_history('block',0) where label='Maker';
select pg_temp.assert_true(count(*)=3 and count(cover_url)=0 and count(preview_path)=0,
  'Blocking the publisher hides cover metadata but keeps report cards') from public.reported_video_history(0);
select public.withdraw_video_report('catalog:narcon-conga-line');
select pg_temp.assert_true(count(*)=0,'Withdrawing a report preserves the block') from public.catalog where id='narcon-conga-line';
delete from public.blocks where target_id='00000000-0000-4000-8000-000000000002';
select pg_temp.assert_true(count(*)=1,'Both reasons removed restores catalog') from public.catalog where id='narcon-conga-line';
select pg_temp.assert_true(count(*)=0,'Unblock preserves independent work report') from public.works where title='Member movie';
select pg_temp.assert_true(count(*)=0,'Unblock preserves independent cosplay report') from public.cosplay_posts where title='Cosplay clip';
select pg_temp.assert_true(count(*)=0,'Private member profile is unreadable') from public.profiles where id='00000000-0000-4000-8000-000000000003';
do $$begin
  begin
    perform public.block_member('00000000-0000-4000-8000-000000000003','30000000-0000-4000-8000-000000000009');
    raise exception 'Unexpected acceptance of unrelated comment' using errcode='23514';
  exception when raise_exception then null;
  end;
end$$;
select public.block_member('00000000-0000-4000-8000-000000000003','30000000-0000-4000-8000-000000000001');
select public.block_member('00000000-0000-4000-8000-000000000003','30000000-0000-4000-8000-000000000001');
select pg_temp.assert_true(count(*)=0,'Private author comments now hidden') from public.comments where id='30000000-0000-4000-8000-000000000001';
select pg_temp.assert_true(count(*)=1,'History identifies private author without revealing a private profile') from public.safety_history('block',0)
 where label='City Resident' and detail not like '%Comment from a private member%' and target_key='00000000-0000-4000-8000-000000000003';
set local request.jwt.claim.sub='00000000-0000-4000-8000-000000000002';
select pg_temp.assert_true(count(*)=0,'Another member cannot see report covers') from public.reported_video_history(0);
select pg_temp.assert_true(count(*)=0,'History is scoped to its owner') from public.safety_history('report',0);
select public.withdraw_video_report('work:10000000-0000-4000-8000-000000000001');
select pg_temp.assert_true(count(*)=1,'Another account still sees reported movie') from public.works where title='Member movie';
set local request.jwt.claim.sub='00000000-0000-4000-8000-000000000001';
select pg_temp.assert_true(count(*)=0,'Another account cannot withdraw my report') from public.works where title='Member movie';
select public.withdraw_video_report('work:10000000-0000-4000-8000-000000000001');
select pg_temp.assert_true(count(*)=1,'Withdrawing last reason restores eligible work') from public.works where title='Member movie';
reset role;
select pg_temp.assert_true(count(*)=2,'Withdrawal is visible to moderators') from public.reports where reporter_id='00000000-0000-4000-8000-000000000001' and withdrawn_at is not null;
set local role authenticated;
select public.submit_video_report('catalog','narcon-conga-line','Spam');
select pg_temp.assert_true(count(*)=0,'Reporting again hides the video again') from public.catalog where id='narcon-conga-line';
reset role;
select pg_temp.assert_true(count(*)=1,'New report opens a new moderation event') from public.reports where reporter_id='00000000-0000-4000-8000-000000000001' and catalog_id='narcon-conga-line' and withdrawn_at is null;
select pg_temp.assert_true(count(*)=4,'Moderator reports survive withdrawal and retries') from public.reports where reporter_id='00000000-0000-4000-8000-000000000001';
select pg_temp.assert_true(count(*)=2,'Exactly one moderator notice per effective block, retained after unblock') from private.block_notices where actor='00000000-0000-4000-8000-000000000001';
select pg_temp.assert_true(count(*)=1,'Developer receives durable offending comment context') from private.block_notices where comment_excerpt='Comment from a private member';
select pg_temp.assert_true(not has_table_privilege('authenticated','private.block_notices','SELECT'),'Member cannot read developer notifications');
update public.cosplay_posts set status='rejected' where title='Cosplay clip';
set local role authenticated;
select public.withdraw_video_report('cosplay:20000000-0000-4000-8000-000000000001');
select pg_temp.assert_true(count(*)=0,'Withdrawal cannot restore a rejected video') from public.cosplay_posts where title='Cosplay clip';
reset role;
insert into private.video_hides(actor,target_key,label,reason,reported_at)
  select '00000000-0000-4000-8000-000000000001'::uuid, 'work:page-' || n, 'Past work', 'Spam',now()
  from generate_series(1,205) n;
set local role authenticated;
select pg_temp.assert_true(count(*)=206 and count(distinct target_key)=206,'Settings can reach every record across three pages')
  from (select * from public.safety_history('report',0) union all select * from public.safety_history('report',100)
    union all select * from public.safety_history('report',200)) entries;
rollback;
