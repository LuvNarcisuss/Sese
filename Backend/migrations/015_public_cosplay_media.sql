do $$
declare
  already_public boolean;
begin
  perform set_config('lock_timeout', '3s', true);
  lock table storage.objects in share mode;
  select public into already_public from storage.buckets where id = 'cosplay-media' for update;
  if not found then
    raise exception 'Apply the Cosplay post migration first';
  end if;
  if already_public then return; end if;
  if exists (select 1 from storage.objects where bucket_id = 'cosplay-media')
     or exists (select 1 from public.cosplay_posts) then
    raise exception 'The bucket contains media submitted under the previous access model';
  end if;
  update storage.buckets set public = true where id = 'cosplay-media';
end;
$$;
