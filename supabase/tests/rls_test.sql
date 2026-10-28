\set ON_ERROR_STOP on
-- fixtures (as superuser)
insert into auth.users (id, raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000a','{"role":"student","full_name":"Student A","phone":"9876543210"}'),
 ('00000000-0000-0000-0000-00000000000b','{"role":"student","full_name":"Student B"}'),
 ('00000000-0000-0000-0000-0000000000c1','{"role":"institute","full_name":"Inst X"}'),
 ('00000000-0000-0000-0000-0000000000c2','{"role":"institute","full_name":"Inst Y"}'),
 ('00000000-0000-0000-0000-0000000000d1','{"role":"tutor","full_name":"Tutor 1"}'),
 ('00000000-0000-0000-0000-0000000000d2','{"role":"tutor","full_name":"Tutor 2"}'),
 ('00000000-0000-0000-0000-0000000000e1','{"role":"admin","full_name":"Mallory"}'),
 ('00000000-0000-0000-0000-0000000000ad','{"role":"student","full_name":"Real Admin"}');
insert into public.user_roles values ('00000000-0000-0000-0000-0000000000ad','admin');

create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', u, false);
  execute 'set role authenticated';
end $$;
create or replace function pg_temp.reset() returns void language plpgsql as $$
begin execute 'reset role'; perform set_config('request.jwt.claim.sub','',false); end $$;
create or replace function pg_temp.expect_fail(sql text, label text) returns void language plpgsql as $$
begin
  begin execute sql; raise exception 'EXPECTED FAILURE DID NOT HAPPEN: %', label;
  exception when insufficient_privilege or check_violation or raise_exception then
    if sqlerrm like 'EXPECTED FAILURE%' then raise; end if;
  end;
end $$;
create or replace function pg_temp.expect_count(sql text, n int, label text) returns void language plpgsql as $$
declare c int;
begin execute 'select count(*) from (' || sql || ') q' into c;
  if c <> n then raise exception 'FAIL %: expected %, got %', label, n, c; end if; end $$;

create or replace function pg_temp.expect_rows(sql text, n int, label text) returns void language plpgsql as $$
declare c int;
begin execute sql; get diagnostics c = row_count;
  if c <> n then raise exception 'FAIL %: expected % rows affected, got %', label, n, c; end if; end $$;

-- 1. self-assigned admin role is ignored
select pg_temp.expect_count($$select 1 from public.user_roles where user_id='00000000-0000-0000-0000-0000000000e1' and role='admin'$$, 0, 'metadata cannot grant admin');
select pg_temp.expect_count($$select 1 from public.user_roles where user_id='00000000-0000-0000-0000-0000000000e1' and role='student'$$, 1, 'fallback to student');

-- 2. student isolation
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select pg_temp.expect_count('select 1 from public.profiles', 1, 'student sees only own profile');
select pg_temp.expect_count('select 1 from public.student_profiles', 1, 'student sees only own prefs');
select pg_temp.expect_fail($$insert into public.user_roles values ('00000000-0000-0000-0000-00000000000a','admin')$$, 'student cannot self-grant admin');
select pg_temp.expect_fail($$insert into public.institutes (slug,name,created_by) values ('x-student','Student Inst','00000000-0000-0000-0000-00000000000a')$$, 'student cannot create institute');
select pg_temp.expect_fail($$insert into public.favourites values ('00000000-0000-0000-0000-00000000000b','institute',gen_random_uuid())$$, 'cannot favourite as someone else');
insert into public.favourites values ('00000000-0000-0000-0000-00000000000a','institute',gen_random_uuid());
select pg_temp.expect_fail($$insert into public.comparison_lists (user_id, institute_ids) values ('00000000-0000-0000-0000-00000000000a', array(select gen_random_uuid() from generate_series(1,5)))$$, 'max 4 compared');
select pg_temp.expect_fail($$select log_admin from (select public.log_admin_action('x','y','z') as log_admin) q$$, 'student cannot write audit');
select pg_temp.reset();
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select pg_temp.expect_count('select 1 from public.favourites', 0, 'B cannot see A favourites');
select pg_temp.reset();

-- 3. institute lifecycle
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
insert into public.institutes (slug,name,created_by,city) values ('inst-x','Institute X','00000000-0000-0000-0000-0000000000c1','Bhopal');
select pg_temp.expect_fail($$insert into public.institutes (slug,name,created_by,status) values ('inst-x2','Institute X2','00000000-0000-0000-0000-0000000000c1','published')$$, 'cannot create as published');
select pg_temp.expect_fail($$insert into public.institutes (slug,name,created_by,verification) values ('inst-x3','Institute X3','00000000-0000-0000-0000-0000000000c1','verified')$$, 'cannot create as verified');
select pg_temp.expect_count('select 1 from public.institute_members', 1, 'creator is member');
select pg_temp.expect_fail($$update public.institutes set status='published' where slug='inst-x'$$, 'cannot self-publish');
select pg_temp.expect_fail($$update public.institutes set verification='verified' where slug='inst-x'$$, 'cannot self-verify');
update public.institutes set status='submitted', tagline='ok' where slug='inst-x';
insert into public.courses (institute_id,name,tuition_fee_inr,published) select id,'Course One',1000,true from public.institutes where slug='inst-x';
insert into public.institute_verification_documents (institute_id,doc_type,storage_path) select id,'registration','x/doc.pdf' from public.institutes where slug='inst-x';
select pg_temp.reset();
select set_config('t.xid', (select id::text from public.institutes where slug='inst-x'), false);

-- other institute and anon cannot see unpublished data
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c2');
select pg_temp.expect_count('select 1 from public.institutes', 0, 'Y cannot see X draft/submitted');
select pg_temp.expect_count('select 1 from public.courses', 0, 'Y cannot see X courses');
select pg_temp.expect_count('select 1 from public.institute_verification_documents', 0, 'Y cannot see X docs');
select pg_temp.expect_fail($$insert into public.institute_verification_documents (institute_id,doc_type,storage_path) values (current_setting('t.xid')::uuid,'registration','y/fake.pdf')$$, 'Y cannot upload docs to X');
select pg_temp.expect_fail($$insert into public.institute_members (institute_id,user_id,member_role) values (current_setting('t.xid')::uuid,'00000000-0000-0000-0000-0000000000c2','owner')$$, 'Y cannot add self as X owner');
select pg_temp.expect_rows($$update public.institutes set name='Hijacked' where id=current_setting('t.xid')::uuid$$, 0, 'Y cannot update X');
select pg_temp.expect_fail($$insert into public.courses (institute_id,name,tuition_fee_inr) values (current_setting('t.xid')::uuid,'Injected',1)$$, 'Y cannot add course to X');
select pg_temp.reset();
set role anon;
select pg_temp.expect_count('select 1 from public.institutes', 0, 'anon sees nothing unpublished');
select pg_temp.expect_fail('select * from public.profiles', 'anon has no profiles access');
reset role;

-- admin publishes + audits
select pg_temp.as_user('00000000-0000-0000-0000-0000000000ad');
update public.institutes set status='published', verification='verified' where slug='inst-x';
select public.log_admin_action('publish_institute','institute','inst-x','{}');
select pg_temp.expect_count('select 1 from public.audit_logs', 1, 'admin reads audit');
select pg_temp.expect_fail('update public.audit_logs set action = ''tampered''', 'audit log is immutable');
select pg_temp.reset();
set role anon;
select pg_temp.expect_count('select 1 from public.institutes', 1, 'anon sees published institute');
select pg_temp.expect_count('select 1 from public.courses', 1, 'anon sees published course');
select pg_temp.expect_fail('select * from public.institute_verification_documents', 'anon has no access to docs');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select pg_temp.expect_count('select 1 from public.audit_logs', 0, 'student cannot read audit');
select pg_temp.reset();

-- 4. tutors
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
insert into public.tutors (user_id,slug,display_name) values ('00000000-0000-0000-0000-0000000000d1','tutor-1','Tutor One');
select pg_temp.reset();
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d2');
select pg_temp.expect_count('select 1 from public.tutors', 0, 'T2 cannot see T1 draft');
select pg_temp.expect_rows($$update public.tutors set display_name='Hacked'$$, 0, 'T2 cannot update T1');
select pg_temp.expect_fail($$insert into public.tutors (user_id,slug,display_name) values ('00000000-0000-0000-0000-0000000000d1','tutor-fake','Impostor')$$, 'T2 cannot create profile for T1');
select pg_temp.reset();
\echo ALL RLS CHECKS PASSED

-- 5. institute_private (run after the fixtures above; Stage 2 migration 0004)
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
insert into public.institute_private (institute_id, contact_person, contact_email, contact_phone)
  values (current_setting('t.xid')::uuid, 'Owner X', 'x@example.com', '9876543210');
select pg_temp.expect_count('select 1 from public.institute_private', 1, 'owner reads own contact');
select pg_temp.reset();
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c2');
select pg_temp.expect_count('select 1 from public.institute_private', 0, 'other institute cannot read contact');
select pg_temp.expect_fail($$insert into public.institute_private (institute_id, contact_person, contact_email, contact_phone) values (current_setting('t.xid')::uuid,'Evil','e@example.com','9876543211')$$, 'other institute cannot write contact');
select pg_temp.reset();
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select pg_temp.expect_count('select 1 from public.institute_private', 0, 'student cannot read contact');
select pg_temp.reset();
set role anon;
select pg_temp.expect_fail('select * from public.institute_private', 'anon cannot read contact');
reset role;
\echo INSTITUTE_PRIVATE CHECKS PASSED

-- 6. onboarding writes: owner can add faculty + batches; other institute cannot
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
insert into public.faculty (institute_id, name, qualification, experience_years) values (current_setting('t.xid')::uuid, 'Dr Test', 'M.Sc', 5);
insert into public.batches (course_id, timing) select id, 'Weekdays 4 PM' from public.courses where institute_id = current_setting('t.xid')::uuid limit 1;
select pg_temp.expect_count('select 1 from public.faculty', 1, 'owner sees own faculty');
select pg_temp.reset();
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c2');
select pg_temp.expect_fail($$insert into public.faculty (institute_id, name) values (current_setting('t.xid')::uuid, 'Intruder')$$, 'other institute cannot add faculty');
select pg_temp.expect_rows($$update public.courses set published = false where institute_id = current_setting('t.xid')::uuid$$, 0, 'other institute cannot unpublish courses');
select pg_temp.reset();
\echo ONBOARDING WRITE CHECKS PASSED
