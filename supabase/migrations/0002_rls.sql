-- EduMatch Stage 2: Row Level Security.
-- Principle: deny by default. Every table has RLS enabled; each policy is explicit.
-- The service-role key bypasses RLS and must only be used server-side.

alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.student_profiles enable row level security;
alter table public.institutes enable row level security;
alter table public.institute_members enable row level security;
alter table public.institute_verification_documents enable row level security;
alter table public.tutors enable row level security;
alter table public.tutor_verification_documents enable row level security;
alter table public.courses enable row level security;
alter table public.batches enable row level security;
alter table public.faculty enable row level security;
alter table public.course_faculty enable row level security;
alter table public.favourites enable row level security;
alter table public.comparison_lists enable row level security;
alter table public.audit_logs enable row level security;

-- Tighten default grants: the API roles get only what policies can then narrow.
revoke all on all tables in schema public from anon, authenticated;
grant select on public.institutes, public.tutors, public.courses, public.batches, public.faculty, public.course_faculty to anon, authenticated;
grant select, update on public.profiles, public.student_profiles to authenticated;
grant select on public.user_roles to authenticated;
grant select, insert, update, delete on public.institutes, public.tutors, public.courses, public.batches, public.faculty, public.course_faculty to authenticated;
grant select, insert, update, delete on public.institute_members to authenticated;
grant select, insert, delete on public.institute_verification_documents, public.tutor_verification_documents to authenticated;
grant update (status, reviewed_by, reviewed_at) on public.institute_verification_documents, public.tutor_verification_documents to authenticated;
grant select, insert, delete on public.favourites to authenticated;
grant select, insert, update, delete on public.comparison_lists to authenticated;
grant select on public.audit_logs to authenticated;
-- Anonymous visitors must never see unpublished rows (enforced by policies below).
revoke insert, update, delete on all tables in schema public from anon;

-- ---------- profiles ----------
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- ---------- user_roles: read-only for users; only service role / migrations assign roles ----------
create policy user_roles_select on public.user_roles for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- ---------- student_profiles ----------
create policy student_profiles_select on public.student_profiles for select to authenticated
  using (user_id = auth.uid());
create policy student_profiles_update on public.student_profiles for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
-- Admins deliberately cannot browse student preferences through the API.

-- ---------- institutes ----------
create policy institutes_public_read on public.institutes for select to anon, authenticated
  using (status = 'published');
create policy institutes_member_read on public.institutes for select to authenticated
  using (public.is_institute_member(id) or public.is_admin());
create policy institutes_create on public.institutes for insert to authenticated
  with check (
    public.has_role('institute') and created_by = auth.uid()
    and status = 'draft' and verification = 'not_verified' and is_demo = false
  );
create policy institutes_member_update on public.institutes for update to authenticated
  using (public.is_institute_member(id, 'manager')) with check (public.is_institute_member(id, 'manager'));
create policy institutes_admin_all on public.institutes for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
-- No member DELETE policy: listings are removed by admins only.

-- ---------- institute_members ----------
create policy members_select on public.institute_members for select to authenticated
  using (user_id = auth.uid() or public.is_institute_member(institute_id, 'owner') or public.is_admin());
create policy members_owner_manage on public.institute_members for all to authenticated
  using (public.is_institute_member(institute_id, 'owner'))
  with check (public.is_institute_member(institute_id, 'owner'));

-- ---------- verification documents (never public) ----------
create policy inst_docs_member_read on public.institute_verification_documents for select to authenticated
  using (public.is_institute_member(institute_id, 'manager') or public.is_admin());
create policy inst_docs_member_insert on public.institute_verification_documents for insert to authenticated
  with check (public.is_institute_member(institute_id, 'manager') and status = 'uploaded' and reviewed_by is null);
create policy inst_docs_member_delete on public.institute_verification_documents for delete to authenticated
  using (public.is_institute_member(institute_id, 'manager') and status = 'uploaded');
create policy inst_docs_admin_review on public.institute_verification_documents for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------- tutors ----------
create policy tutors_public_read on public.tutors for select to anon, authenticated
  using (status = 'published');
create policy tutors_own_read on public.tutors for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy tutors_create on public.tutors for insert to authenticated
  with check (
    public.has_role('tutor') and user_id = auth.uid()
    and status = 'draft' and verification = 'not_verified' and is_demo = false
  );
create policy tutors_own_update on public.tutors for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy tutors_admin_all on public.tutors for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy tutor_docs_own_read on public.tutor_verification_documents for select to authenticated
  using (exists (select 1 from public.tutors t where t.id = tutor_id and t.user_id = auth.uid()) or public.is_admin());
create policy tutor_docs_own_insert on public.tutor_verification_documents for insert to authenticated
  with check (exists (select 1 from public.tutors t where t.id = tutor_id and t.user_id = auth.uid())
              and status = 'uploaded' and reviewed_by is null);
create policy tutor_docs_own_delete on public.tutor_verification_documents for delete to authenticated
  using (exists (select 1 from public.tutors t where t.id = tutor_id and t.user_id = auth.uid()) and status = 'uploaded');
create policy tutor_docs_admin_review on public.tutor_verification_documents for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------- courses / batches / faculty ----------
create policy courses_public_read on public.courses for select to anon, authenticated
  using (published and exists (select 1 from public.institutes i where i.id = institute_id and i.status = 'published'));
create policy courses_member_all on public.courses for all to authenticated
  using (public.is_institute_member(institute_id, 'manager') or public.is_admin())
  with check (public.is_institute_member(institute_id, 'manager') or public.is_admin());
create policy courses_member_read on public.courses for select to authenticated
  using (public.is_institute_member(institute_id));

create policy batches_public_read on public.batches for select to anon, authenticated
  using (exists (select 1 from public.courses c join public.institutes i on i.id = c.institute_id
                 where c.id = course_id and c.published and i.status = 'published'));
create policy batches_member_all on public.batches for all to authenticated
  using (exists (select 1 from public.courses c where c.id = course_id
                 and (public.is_institute_member(c.institute_id, 'manager') or public.is_admin())))
  with check (exists (select 1 from public.courses c where c.id = course_id
                 and (public.is_institute_member(c.institute_id, 'manager') or public.is_admin())));

create policy faculty_public_read on public.faculty for select to anon, authenticated
  using (exists (select 1 from public.institutes i where i.id = institute_id and i.status = 'published'));
create policy faculty_member_all on public.faculty for all to authenticated
  using (public.is_institute_member(institute_id, 'manager') or public.is_admin())
  with check (public.is_institute_member(institute_id, 'manager') or public.is_admin());

create policy course_faculty_public_read on public.course_faculty for select to anon, authenticated
  using (exists (select 1 from public.courses c join public.institutes i on i.id = c.institute_id
                 where c.id = course_id and c.published and i.status = 'published'));
create policy course_faculty_member_all on public.course_faculty for all to authenticated
  using (exists (select 1 from public.courses c where c.id = course_id
                 and (public.is_institute_member(c.institute_id, 'manager') or public.is_admin())))
  with check (
    exists (select 1 from public.courses c where c.id = course_id
            and (public.is_institute_member(c.institute_id, 'manager') or public.is_admin()))
    -- faculty must belong to the same institute as the course
    and exists (select 1 from public.courses c join public.faculty f on f.institute_id = c.institute_id
                where c.id = course_id and f.id = faculty_id)
  );

-- ---------- favourites / comparison lists (strictly own rows) ----------
create policy favourites_own on public.favourites for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy comparison_own on public.comparison_lists for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- audit_logs: admins read; nobody writes directly (use log_admin_action) ----------
create policy audit_admin_read on public.audit_logs for select to authenticated
  using (public.is_admin());

-- Helper functions must be callable by API roles; table access is still gated by the policies above.
grant execute on function public.has_role(public.app_role), public.is_admin(),
  public.is_institute_member(uuid, public.member_role), public.log_admin_action(text, text, text, jsonb) to authenticated;
grant execute on function public.has_role(public.app_role), public.is_admin(),
  public.is_institute_member(uuid, public.member_role) to anon;
revoke execute on function public.log_admin_action(text, text, text, jsonb) from anon, public;
