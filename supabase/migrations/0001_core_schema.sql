-- EduMatch Stage 2: core schema, helper functions, triggers.
-- RLS policies live in 0002_rls.sql. Storage policies in 0003_storage.sql.
-- Enquiries, consent, lead and payment tables are added in Stage 3.

create extension if not exists pgcrypto;

-- ---------- Enums ----------
create type public.app_role as enum ('student', 'institute', 'tutor', 'admin');
create type public.listing_status as enum ('draft', 'submitted', 'published', 'suspended', 'rejected');
create type public.verification_status as enum ('not_verified', 'pending_review', 'verified');
create type public.teaching_mode as enum ('online', 'offline', 'hybrid');
create type public.member_role as enum ('owner', 'manager', 'staff');
create type public.document_status as enum ('uploaded', 'accepted', 'rejected');
create type public.favourite_type as enum ('institute', 'tutor');

-- ---------- Generic helpers ----------
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ---------- Profiles and roles ----------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null check (char_length(full_name) between 2 and 120),
  phone text check (phone is null or phone ~ '^[6-9][0-9]{9}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_roles (
  user_id uuid not null references auth.users (id) on delete cascade,
  role public.app_role not null,
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);

-- SECURITY DEFINER helpers avoid RLS recursion and are the single source of truth for role checks.
create or replace function public.has_role(_role public.app_role) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles where user_id = auth.uid() and role = _role);
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select public.has_role('admin');
$$;

-- New auth user -> profile + exactly one self-selectable role. 'admin' can NEVER be self-assigned.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  requested text := new.raw_user_meta_data ->> 'role';
  chosen public.app_role := 'student';
  phone_raw text := nullif(regexp_replace(coalesce(new.raw_user_meta_data ->> 'phone', ''), '^(\+91|0)', ''), '');
begin
  if requested in ('institute', 'tutor') then
    chosen := requested::public.app_role;
  end if;

  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), 'New user'),
    case when phone_raw ~ '^[6-9][0-9]{9}$' then phone_raw else null end
  );
  insert into public.user_roles (user_id, role) values (new.id, chosen);
  if chosen = 'student' then
    insert into public.student_profiles (user_id) values (new.id);
  end if;
  return new;
end $$;

-- ---------- Student profile (private) ----------
create table public.student_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  budget_min integer check (budget_min >= 0),
  budget_max integer check (budget_max >= 0),
  city text,
  courses text[] not null default '{}',
  languages text[] not null default '{}',
  preferred_mode public.teaching_mode,
  updated_at timestamptz not null default now(),
  check (budget_max is null or budget_min is null or budget_max >= budget_min)
);

-- Guardian records are created and enforced in Stage 3 with the consent workflow.

-- ---------- Institutes ----------
create table public.institutes (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name text not null check (char_length(name) between 3 and 150),
  tagline text check (char_length(tagline) <= 160),
  about text,
  city text,
  locality text,
  address text,
  pincode text check (pincode is null or pincode ~ '^[1-9][0-9]{5}$'),
  categories text[] not null default '{}',
  modes public.teaching_mode[] not null default '{}',
  languages text[] not null default '{}',
  facilities text[] not null default '{}',
  refund_policy text,
  status public.listing_status not null default 'draft',
  verification public.verification_status not null default 'not_verified',
  is_demo boolean not null default false,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index institutes_public_idx on public.institutes (city, status) where status = 'published';
create index institutes_created_by_idx on public.institutes (created_by);

create table public.institute_members (
  institute_id uuid not null references public.institutes (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  member_role public.member_role not null default 'staff',
  created_at timestamptz not null default now(),
  primary key (institute_id, user_id)
);
create index institute_members_user_idx on public.institute_members (user_id);

create or replace function public.is_institute_member(_institute uuid, _min_role public.member_role default 'staff')
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.institute_members m
    where m.institute_id = _institute and m.user_id = auth.uid()
      and case _min_role
            when 'staff' then true
            when 'manager' then m.member_role in ('manager', 'owner')
            when 'owner' then m.member_role = 'owner'
          end
  );
$$;

-- Creator becomes owner automatically.
create or replace function public.add_institute_owner() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.created_by is not null then
    insert into public.institute_members (institute_id, user_id, member_role)
    values (new.id, new.created_by, 'owner') on conflict do nothing;
  end if;
  return new;
end $$;

create table public.institute_verification_documents (
  id uuid primary key default gen_random_uuid(),
  institute_id uuid not null references public.institutes (id) on delete cascade,
  doc_type text not null check (char_length(doc_type) between 2 and 60),
  storage_path text not null,
  status public.document_status not null default 'uploaded',
  reviewed_by uuid references auth.users (id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index inst_docs_institute_idx on public.institute_verification_documents (institute_id);

-- ---------- Tutors ----------
create table public.tutors (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users (id) on delete cascade,
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  display_name text not null check (char_length(display_name) between 2 and 120),
  headline text check (char_length(headline) <= 160),
  about text,
  city text,
  service_localities text[] not null default '{}',
  subjects text[] not null default '{}',
  levels text[] not null default '{}',
  online boolean not null default true,
  home boolean not null default false,
  languages text[] not null default '{}',
  experience_years integer check (experience_years between 0 and 70),
  qualifications text[] not null default '{}',
  hourly_fee_inr integer check (hourly_fee_inr >= 0),
  monthly_fee_inr integer check (monthly_fee_inr >= 0),
  availability text[] not null default '{}',
  demo_available boolean not null default false,
  status public.listing_status not null default 'draft',
  verification public.verification_status not null default 'not_verified',
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index tutors_public_idx on public.tutors (city, status) where status = 'published';

create table public.tutor_verification_documents (
  id uuid primary key default gen_random_uuid(),
  tutor_id uuid not null references public.tutors (id) on delete cascade,
  doc_type text not null check (char_length(doc_type) between 2 and 60),
  storage_path text not null,
  status public.document_status not null default 'uploaded',
  reviewed_by uuid references auth.users (id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

-- ---------- Courses, batches, faculty ----------
create table public.courses (
  id uuid primary key default gen_random_uuid(),
  institute_id uuid not null references public.institutes (id) on delete cascade,
  name text not null check (char_length(name) between 3 and 150),
  exam text,
  level text,
  duration_months integer check (duration_months > 0),
  tuition_fee_inr integer not null check (tuition_fee_inr >= 0),
  other_fees_inr integer not null default 0 check (other_fees_inr >= 0),
  mode public.teaching_mode not null default 'offline',
  batch_size integer check (batch_size > 0),
  syllabus text,
  demo_enabled boolean not null default false,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index courses_institute_idx on public.courses (institute_id);
create index courses_exam_idx on public.courses (exam) where published;

create table public.batches (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete cascade,
  timing text not null check (char_length(timing) between 3 and 120),
  seats_total integer check (seats_total >= 0),
  seats_available integer check (seats_available >= 0),
  created_at timestamptz not null default now(),
  check (seats_available is null or seats_total is null or seats_available <= seats_total)
);
create index batches_course_idx on public.batches (course_id);

create table public.faculty (
  id uuid primary key default gen_random_uuid(),
  institute_id uuid not null references public.institutes (id) on delete cascade,
  name text not null check (char_length(name) between 2 and 120),
  qualification text,
  experience_years integer check (experience_years between 0 and 70),
  subjects text[] not null default '{}',
  created_at timestamptz not null default now()
);
create index faculty_institute_idx on public.faculty (institute_id);

create table public.course_faculty (
  course_id uuid not null references public.courses (id) on delete cascade,
  faculty_id uuid not null references public.faculty (id) on delete cascade,
  primary key (course_id, faculty_id)
);

-- ---------- Favourites and comparison (private) ----------
create table public.favourites (
  user_id uuid not null references auth.users (id) on delete cascade,
  target_type public.favourite_type not null,
  target_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (user_id, target_type, target_id)
);

create table public.comparison_lists (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null default 'My comparison' check (char_length(name) <= 80),
  institute_ids uuid[] not null default '{}' check (cardinality(institute_ids) <= 4),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index comparison_lists_user_idx on public.comparison_lists (user_id);

-- ---------- Audit log (append-only) ----------
create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users (id) on delete set null,
  action text not null,
  target_type text,
  target_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index audit_logs_created_idx on public.audit_logs (created_at desc);

create or replace function public.audit_logs_immutable() returns trigger
language plpgsql as $$
begin
  raise exception 'audit_logs is append-only';
end $$;

create trigger audit_logs_no_update before update or delete on public.audit_logs
  for each row execute function public.audit_logs_immutable();

-- Admin-only writer. Everything sensitive an admin does should go through this.
create or replace function public.log_admin_action(_action text, _target_type text, _target_id text, _details jsonb default '{}')
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (auth.uid(), _action, _target_type, _target_id, coalesce(_details, '{}'));
end $$;

-- ---------- Guard: owners may not change moderation fields ----------
create or replace function public.guard_listing_moderation() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- Service role / migrations (no JWT user) and admins are unrestricted.
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if new.verification is distinct from old.verification or new.is_demo is distinct from old.is_demo then
    raise exception 'only an administrator can change verification or demo flags' using errcode = '42501';
  end if;
  if new.status is distinct from old.status
     and not ((old.status in ('draft', 'rejected') and new.status = 'submitted')
              or (old.status = 'submitted' and new.status = 'draft')) then
    raise exception 'status change not permitted' using errcode = '42501';
  end if;
  return new;
end $$;

-- ---------- Triggers ----------
create trigger profiles_updated before update on public.profiles for each row execute function public.set_updated_at();
create trigger student_profiles_updated before update on public.student_profiles for each row execute function public.set_updated_at();
create trigger institutes_updated before update on public.institutes for each row execute function public.set_updated_at();
create trigger tutors_updated before update on public.tutors for each row execute function public.set_updated_at();
create trigger courses_updated before update on public.courses for each row execute function public.set_updated_at();
create trigger comparison_lists_updated before update on public.comparison_lists for each row execute function public.set_updated_at();

create trigger institutes_guard before update on public.institutes for each row execute function public.guard_listing_moderation();
create trigger tutors_guard before update on public.tutors for each row execute function public.guard_listing_moderation();
create trigger institutes_owner after insert on public.institutes for each row execute function public.add_institute_owner();

create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
