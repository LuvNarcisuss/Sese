-- Safe to run against the deployed migration. All test records are rolled back.
begin;
create function pg_temp.safety_id(k text) returns uuid language sql stable as
$$ select current_setting('sese_check.' || k)::uuid $$;
create function pg_temp.safety_check(ok boolean, description text) returns void language plpgsql as
$$ begin if ok is distinct from true then raise exception 'Moderation check failed: %',description; end if; end $$;
select set_config('sese_check.' || k,gen_random_uuid()::text,true)
from unnest(array['viewer','other','author','first','second','own','message','request']) k;
insert into auth.users(id) select pg_temp.safety_id(k) from unnest(array['viewer','other','author']) k;
insert into public.profiles(id) select pg_temp.safety_id(k) from unnest(array['viewer','other','author']) k;
insert into public.comments(id,author_id,catalog_id,body)
values(pg_temp.safety_id('first'),pg_temp.safety_id('author'),'costume-meetup-hug','First moderation check'),
      (pg_temp.safety_id('second'),pg_temp.safety_id('author'),'costume-meetup-hug','Second moderation check'),
      (pg_temp.safety_id('own'),pg_temp.safety_id('viewer'),'costume-meetup-hug','Viewer comment');
select set_config('request.jwt.claim.sub',pg_temp.safety_id('viewer')::text,true);
set local role authenticated;
select set_config('sese_check.before_count',comments::text,true) from public.short_counts(array['costume-meetup-hug']);
select public.submit_item_report('member',pg_temp.safety_id('author')::text,'comment:' || pg_temp.safety_id('first'),'Spam',pg_temp.safety_id('request'));
select public.submit_item_report('member',pg_temp.safety_id('author')::text,'comment:' || pg_temp.safety_id('first'),'Spam',pg_temp.safety_id('request'));
do $$begin
  begin
    insert into public.blocks(target_id) values(pg_temp.safety_id('author'));
    raise exception 'Unexpected direct block' using errcode='23514';
  exception when insufficient_privilege then null; end;
  begin
    perform public.submit_comment_report(pg_temp.safety_id('own'),'Spam');
    raise exception 'Unexpected self report' using errcode='23514';
  exception when insufficient_privilege then null; end;
  begin
    perform public.submit_item_report('member',pg_temp.safety_id('other')::text,'comment:' || pg_temp.safety_id('first'),'Spam',gen_random_uuid());
    raise exception 'Unexpected author mismatch' using errcode='23514';
  exception when insufficient_privilege then null; end;
end$$;
select public.submit_comment_report(pg_temp.safety_id('first'),'Spam');
select public.submit_comment_report(pg_temp.safety_id('first'),'Spam');
select pg_temp.safety_check(not exists(select from public.comments where id=pg_temp.safety_id('first'))
  and exists(select from public.comments where id=pg_temp.safety_id('second')),'Only the reported comment disappears');
select pg_temp.safety_check(comments=current_setting('sese_check.before_count')::int-1,'Parent remains visible with adjusted count')
from public.short_counts(array['costume-meetup-hug']);
select pg_temp.safety_check(count(*)=1 and min(label)='First moderation check' and min(detail) like 'City Resident%',
  'One identifiable private comment history record') from public.reported_comment_history(0);
select set_config('request.jwt.claim.sub',pg_temp.safety_id('other')::text,true);
select pg_temp.safety_check(exists(select from public.comments where id=pg_temp.safety_id('first'))
  and not exists(select from public.reported_comment_history(0)),'Second account unaffected');
select set_config('request.jwt.claim.sub',pg_temp.safety_id('viewer')::text,true);
select public.block_from_source(pg_temp.safety_id('author'),'comment:' || pg_temp.safety_id('second'));
delete from public.blocks where target_id=pg_temp.safety_id('author');
select pg_temp.safety_check(not exists(select from public.comments where id=pg_temp.safety_id('first'))
  and exists(select from public.comments where id=pg_temp.safety_id('second')),'Unblocking preserves report');
select public.block_from_source(pg_temp.safety_id('author'),'comment:' || pg_temp.safety_id('second'));
select public.withdraw_comment_report(pg_temp.safety_id('first'));
select pg_temp.safety_check(not exists(select from public.comments where author_id=pg_temp.safety_id('author')),
  'Withdrawing preserves block');
delete from public.blocks where target_id=pg_temp.safety_id('author');
select pg_temp.safety_check(count(*)=2,'Both eligible comments restored') from public.comments where author_id=pg_temp.safety_id('author');
select public.submit_comment_report(pg_temp.safety_id('first'),'Other');
reset role;
delete from public.comments where id=pg_temp.safety_id('first');
insert into public.messages(id,sender_id,recipient_id,body) values
  (pg_temp.safety_id('message'),pg_temp.safety_id('viewer'),pg_temp.safety_id('author'),'Thread moderation check');
set local role authenticated;
do $$begin
  begin
    insert into public.reports(message_id,reason) values(pg_temp.safety_id('message'),'Other');
    raise exception 'Unexpected report of own message' using errcode='23514';
  exception when insufficient_privilege then null; end;
end$$;
select public.block_from_source(pg_temp.safety_id('author'),null);
select pg_temp.safety_check(not exists(select from public.messages where id=pg_temp.safety_id('message')),'Private chat block');
select public.withdraw_comment_report(pg_temp.safety_id('first'));
select pg_temp.safety_check(not exists(select from public.reported_comment_history(0)),'Withdraw after source deletion');
reset role;
select pg_temp.safety_check(count(*)=2 and bool_and(withdrawn_at is not null) and min(excerpt)='First moderation check',
  'Receipts survive source deletion and retain withdrawal') from private.report_receipts
  where actor=pg_temp.safety_id('viewer') and target_key='comment:' || pg_temp.safety_id('first');
select pg_temp.safety_check(count(*)=1 and min(source_excerpt)='First moderation check','Author report retry and context')
  from private.report_receipts where actor=pg_temp.safety_id('viewer') and target_key='member:' || pg_temp.safety_id('author');
select pg_temp.safety_check(count(*)=2 and min(source_excerpt)='Second moderation check','Block context survives undo')
  from private.block_notices where actor=pg_temp.safety_id('viewer') and comment_id=pg_temp.safety_id('second');
select pg_temp.safety_check(not has_table_privilege('authenticated','private.report_receipts','select'),'Private operator evidence');
select 'Comment moderation scenarios passed' as verification;
rollback;
