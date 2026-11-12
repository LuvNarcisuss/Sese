create table public.works (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references public.profiles on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 80),
  caption text not null default '' check (char_length(caption) <= 350),
  source_url text not null check (source_url ~ '^https://www[.]youtube[.]com/watch[?]v=[A-Za-z0-9_-]{11}$'),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now()
);
create index works_owner_created_idx on public.works(owner_id, created_at desc);
create index works_status_created_idx on public.works(created_at desc) where status = 'approved';
alter table public.works enable row level security;
revoke all on public.works from public, anon, authenticated;
grant select, delete on public.works to authenticated;
grant insert (title, caption, source_url) on public.works to authenticated;
create policy works_read on public.works for select to authenticated using (
  owner_id = (select auth.uid()) or
  (status = 'approved' and not private.is_blocked(owner_id)
    and exists(select 1 from public.profiles where id = owner_id and discoverable))
);
create policy works_submit on public.works for insert to authenticated
  with check (owner_id = (select auth.uid()) and status = 'pending');
create policy works_remove on public.works for delete to authenticated
  using (owner_id = (select auth.uid()));

alter table public.reports add column work_id uuid references public.works on delete cascade;
alter table public.reports drop constraint reports_check;
alter table public.reports add constraint report_one_target
  check (num_nonnulls(reported_id, catalog_id, comment_id, message_id, work_id) = 1);
grant insert (work_id) on public.reports to authenticated;
alter policy reports_add on public.reports with check (reporter_id = (select auth.uid()) and
  (message_id is null or exists (select 1 from public.messages m where m.id = message_id)) and
  (comment_id is null or exists (select 1 from public.comments c where c.id = comment_id)) and
  (work_id is null or exists (select 1 from public.works w where w.id = work_id)));
