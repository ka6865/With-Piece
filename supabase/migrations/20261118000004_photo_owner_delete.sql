-- 사진은 올린 사람만 지운다(설계 8.0). 화면에서만 막으면 API 직접 호출로 상대 사진을
-- 지울 수 있어 행과 파일 모두 정책으로 막는다. 정리 작업은 service role이라 받지 않는다
drop policy photos_delete on public.photos;
create policy photos_delete on public.photos
  for delete to authenticated using (
    couple_id = (select private.my_couple_id())
    and uploaded_by = (select auth.uid())
  );

drop policy photos_bucket_delete on storage.objects;
create policy photos_bucket_delete on storage.objects
  for delete to authenticated using (
    bucket_id = 'photos'
    and (storage.foldername(name))[1]::uuid = (select private.my_couple_id())
    and owner = (select auth.uid())
  );
