-- Private institute contact details. Kept out of `institutes` because that table is publicly readable.
create table public.institute_private (
  institute_id uuid primary key references public.institutes (id) on delete cascade,
  contact_person text not null check (char_length(contact_person) between 2 and 120),
  contact_email text not null,
  contact_phone text not null check (contact_phone ~ '^[6-9][0-9]{9}$'),
  state text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger institute_private_updated before update on public.institute_private
  for each row execute function public.set_updated_at();

alter table public.institute_private enable row level security;
revoke all on public.institute_private from anon, authenticated;
grant select, insert, update on public.institute_private to authenticated;

create policy inst_private_read on public.institute_private for select to authenticated
  using (public.is_institute_member(institute_id, 'manager') or public.is_admin());
create policy inst_private_insert on public.institute_private for insert to authenticated
  with check (public.is_institute_member(institute_id, 'owner'));
create policy inst_private_update on public.institute_private for update to authenticated
  using (public.is_institute_member(institute_id, 'manager'))
  with check (public.is_institute_member(institute_id, 'manager'));
