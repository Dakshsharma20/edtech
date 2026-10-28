-- Private bucket for verification documents. Path convention: <institute-or-tutor-id>/<filename>.
-- Run via the Supabase CLI / SQL editor on a project where the storage schema exists.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('verification-docs', 'verification-docs', false, 5242880, array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do nothing;

create policy verification_docs_read on storage.objects for select to authenticated
  using (bucket_id = 'verification-docs' and (
    public.is_admin()
    or public.is_institute_member(((storage.foldername(name))[1])::uuid, 'manager')
    or exists (select 1 from public.tutors t where t.id::text = (storage.foldername(name))[1] and t.user_id = auth.uid())
  ));

create policy verification_docs_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'verification-docs' and (
    public.is_institute_member(((storage.foldername(name))[1])::uuid, 'manager')
    or exists (select 1 from public.tutors t where t.id::text = (storage.foldername(name))[1] and t.user_id = auth.uid())
  ));

create policy verification_docs_delete on storage.objects for delete to authenticated
  using (bucket_id = 'verification-docs' and (
    public.is_institute_member(((storage.foldername(name))[1])::uuid, 'manager')
    or exists (select 1 from public.tutors t where t.id::text = (storage.foldername(name))[1] and t.user_id = auth.uid())
  ));
