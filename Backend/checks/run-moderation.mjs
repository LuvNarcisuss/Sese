// Run from the repository root. Set PGLITE_MODULE to a local installation if necessary.
import fs from 'node:fs'

const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite')
const db = new PGlite()
await db.exec(`
create role authenticated; create role anon; create role service_role bypassrls;
create schema auth; create schema storage;
create table auth.users(id uuid primary key, is_anonymous boolean, raw_app_meta_data jsonb);
create table auth.identities(user_id uuid, provider text);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
grant usage on schema auth to authenticated, anon;
create table storage.objects(bucket_id text,name text,owner_id text,metadata jsonb);
create table storage.buckets(id text primary key,name text,public boolean,allowed_mime_types text[],file_size_limit bigint);
create function storage.allow_any_operation(text[]) returns boolean language sql stable as $$select true$$;
create publication supabase_realtime;`)
for (const file of fs.readdirSync('Backend/migrations').filter(name => name.endsWith('.sql')).sort()) {
  if (file.startsWith('018_')) {
    await db.exec(`
   insert into auth.users(id) values ('90000000-0000-4000-8000-000000000001'), ('90000000-0000-4000-8000-000000000002');
   insert into public.profiles(id,discoverable,display_name)
     values ('90000000-0000-4000-8000-000000000001',true,'Previous viewer'),
            ('90000000-0000-4000-8000-000000000002',true,'Previous maker');
   insert into public.reports(reporter_id,catalog_id,reason) values
     ('90000000-0000-4000-8000-000000000001','narcon-conga-line','Harassment'),
     ('90000000-0000-4000-8000-000000000001','narcon-conga-line','Spam');
   insert into public.blocks(blocker_id,target_id) values
     ('90000000-0000-4000-8000-000000000001','90000000-0000-4000-8000-000000000002');`)
  }
  try {
    await db.exec(fs.readFileSync('Backend/migrations/' + file, 'utf8'))
  } catch (error) {
    throw new Error(file + ': ' + error.message, { cause: error })
  }
}
console.log('All migrations applied')
await db.exec(`
  set role authenticated;
  set request.jwt.claim.sub='90000000-0000-4000-8000-000000000001';
  do $$begin
    if exists(select 1 from public.catalog where id='narcon-conga-line') or
       (select count(*) from public.safety_history('report',0)) <> 1 or
       not exists (select 1 from public.safety_history('block',0) where label='Previous maker')
    then raise exception 'Historical records failed migration'; end if;
  end$$;
  select public.withdraw_video_report('catalog:narcon-conga-line');
  reset role;
  do $$begin
    if (select count(*) from public.reports where withdrawn_at is not null) <> 2 then
      raise exception 'Both historical reports must retain the withdrawal'; end if;
  end$$;`)
console.log('Historical block and duplicate legacy reports migrated')
await db.exec(fs.readFileSync('Backend/checks/moderation.sql', 'utf8'))
console.log('Moderation scenarios passed')
await db.close()
