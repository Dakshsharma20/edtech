-- FICTIONAL DEMO DATA. Run only on development projects. Every row has is_demo = true.
-- Demo rows are published so public pages render, but are never marked verified.
insert into public.institutes (slug, name, tagline, about, city, locality, address, categories, modes, languages, facilities, refund_policy, status, verification, is_demo)
values
 ('demo-vidya-sagar-academy-bhopal', 'Demo Vidya Sagar Academy', 'Fictional JEE & NEET coaching for UI preview',
  'Fictional institute for layout preview. Not a real organisation.', 'Bhopal', 'Arera Colony', 'Demo address, Arera Colony, Bhopal, Madhya Pradesh',
  '{"Engineering Entrance","Medical Entrance"}', '{offline,hybrid}', '{English,Hindi}', '{"Library","Doubt-clearing hours","Weekly tests"}',
  'Demo text: confirm the written refund policy before paying any fee.', 'published', 'not_verified', true),
 ('demo-nalanda-classes-indore', 'Demo Nalanda Classes', 'Fictional foundation & board coaching',
  'Fictional listing for layout testing.', 'Indore', 'Vijay Nagar', 'Demo address, Vijay Nagar, Indore, Madhya Pradesh',
  '{"School Boards","Foundation"}', '{offline}', '{Hindi,English}', '{"Smart classrooms","Printed notes"}',
  'Demo text: confirm the written refund policy before paying any fee.', 'published', 'pending_review', true)
on conflict (slug) do nothing;

insert into public.courses (institute_id, name, exam, level, duration_months, tuition_fee_inr, other_fees_inr, mode, batch_size, demo_enabled, published)
select i.id, c.name, c.exam, c.level, c.dur, c.fee, c.other, c.mode::public.teaching_mode, c.batch, c.demo, true
from public.institutes i
join (values
  ('demo-vidya-sagar-academy-bhopal', 'JEE Main & Advanced – 2-Year Programme', 'JEE Main & Advanced', 'Class 11–12', 24, 165000, 12000, 'offline', 40, true),
  ('demo-vidya-sagar-academy-bhopal', 'NEET – 1-Year Classroom Programme', 'NEET', 'Class 12 / Dropper', 12, 98000, 8000, 'hybrid', 50, true),
  ('demo-nalanda-classes-indore', 'CBSE Class 10 – Science & Maths', 'CBSE Board', 'Class 10', 10, 28000, 2000, 'offline', 25, true)
) as c(slug, name, exam, level, dur, fee, other, mode, batch, demo) on c.slug = i.slug
where not exists (select 1 from public.courses x where x.institute_id = i.id and x.name = c.name);

insert into public.tutors (slug, display_name, headline, about, city, service_localities, subjects, levels, online, home, languages, experience_years, qualifications, hourly_fee_inr, monthly_fee_inr, availability, demo_available, status, verification, is_demo)
values
 ('demo-ananya-iyer-maths', 'Ananya Iyer (demo)', 'Fictional Maths tutor for Class 9–12', 'Sample tutor profile. Not a real person.', 'Bhopal',
  '{"Arera Colony","Shahpura"}', '{Mathematics}', '{"Class 9–10","Class 11–12"}', true, true, '{English,Hindi}', 8,
  '{"M.Sc. Mathematics (supplied by tutor, not verified)"}', 600, 6000, '{"Weekdays 5 PM – 8 PM"}', true, 'published', 'not_verified', true)
on conflict (slug) do nothing;
