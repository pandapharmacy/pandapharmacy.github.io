-- 商品照片的儲存空間（公開讀取；後台上傳照片用）
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-images', 'product-images', true, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = 3145728,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists "panda upload product images" on storage.objects;
create policy "panda upload product images" on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'product-images' and (storage.foldername(name))[1] = 'p');
