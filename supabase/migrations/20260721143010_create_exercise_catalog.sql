create table public.exercise_catalog (
  key text primary key,
  name_en text not null,
  name_uk text not null,
  muscle_ids text[] not null,
  display_order integer not null unique,
  constraint exercise_catalog_key_format check (key ~ '^[a-z0-9_]{1,64}$'),
  constraint exercise_catalog_name_en_length check (char_length(name_en) between 1 and 160),
  constraint exercise_catalog_name_uk_length check (char_length(name_uk) between 1 and 160),
  constraint exercise_catalog_muscles_present check (cardinality(muscle_ids) between 1 and 15),
  constraint exercise_catalog_muscles_known check (
    muscle_ids <@ array[
      'chest', 'shoulders', 'biceps', 'triceps', 'forearms', 'abs', 'obliques',
      'lats', 'upperBack', 'lowerBack', 'glutes', 'quads', 'hamstrings',
      'adductors', 'calves'
    ]::text[]
  )
);

alter table public.exercise_catalog enable row level security;
revoke all on table public.exercise_catalog from anon, authenticated;
grant select on table public.exercise_catalog to anon, authenticated;

create policy exercise_catalog_public_read
on public.exercise_catalog
for select
to anon, authenticated
using (true);

insert into public.exercise_catalog (key, name_en, name_uk, muscle_ids, display_order) values
  ('bench_press', 'Bench Press', 'Жим штанги лежачи', array['chest','triceps','shoulders'], 1),
  ('dumbbell_bench_press', 'Dumbbell Bench Press', 'Жим гантелей лежачи', array['chest','triceps','shoulders'], 2),
  ('incline_dumbbell_press', 'Incline Dumbbell Press', 'Жим гантелей на похилій лаві', array['chest','shoulders','triceps'], 3),
  ('incline_bench_press', 'Incline Bench Press', 'Жим штанги на похилій лаві', array['chest','shoulders','triceps'], 4),
  ('chest_fly_machine', 'Machine Chest Fly', 'Зведення рук у тренажері', array['chest','shoulders'], 5),
  ('push_up', 'Push Up', 'Віджимання від підлоги', array['chest','triceps','shoulders'], 6),
  ('dips', 'Dips', 'Віджимання на брусах', array['triceps','chest','shoulders'], 7),
  ('pull_up', 'Pull Up', 'Підтягування', array['lats','biceps','upperBack','forearms'], 8),
  ('assisted_pull_up', 'Assisted Pull Up', 'Підтягування у гравітроні', array['lats','upperBack','biceps','forearms'], 9),
  ('band_assisted_pull_up', 'Band Assisted Pull Up', 'Підтягування з еспандером', array['lats','upperBack','biceps','forearms'], 10),
  ('lat_pulldown', 'Lat Pulldown', 'Тяга верхнього блока', array['lats','upperBack','biceps','forearms'], 11),
  ('straight_arm_pulldown', 'Straight Arm Pulldown', 'Тяга прямих рук на верхньому блоці', array['lats','upperBack'], 12),
  ('barbell_row', 'Barbell Row', 'Тяга штанги в нахилі', array['upperBack','lats','biceps','forearms'], 13),
  ('seated_cable_row', 'Seated Cable Row', 'Горизонтальна тяга блока', array['upperBack','lats','biceps','forearms'], 14),
  ('plate_loaded_row', 'Plate Loaded Row', 'Горизонтальна тяга у важільному тренажері', array['upperBack','lats','biceps','forearms'], 15),
  ('face_pull', 'Face Pull', 'Тяга каната до обличчя', array['shoulders','upperBack'], 16),
  ('squat', 'Squat', 'Присідання зі штангою', array['quads','glutes','hamstrings','adductors','lowerBack'], 17),
  ('leg_press', 'Leg Press', 'Жим ногами у тренажері', array['quads','glutes','hamstrings'], 18),
  ('bulgarian_split_squat', 'Bulgarian Split Squat', 'Болгарські випади', array['quads','glutes','hamstrings'], 19),
  ('lunge', 'Lunge', 'Випади', array['quads','glutes','hamstrings'], 20),
  ('romanian_deadlift', 'Romanian Deadlift', 'Румунська тяга', array['hamstrings','glutes','lowerBack'], 21),
  ('deadlift', 'Deadlift', 'Станова тяга', array['hamstrings','glutes','lowerBack','upperBack','forearms'], 22),
  ('hip_thrust', 'Hip Thrust', 'Ягодичний міст зі штангою', array['glutes','hamstrings'], 23),
  ('leg_extension', 'Leg Extension', 'Розгинання ніг у тренажері', array['quads'], 24),
  ('lying_leg_curl', 'Lying Leg Curl', 'Згинання ніг лежачи', array['hamstrings','calves'], 25),
  ('seated_leg_curl', 'Seated Leg Curl', 'Згинання ніг сидячи', array['hamstrings','calves'], 26),
  ('hip_adduction', 'Hip Adduction', 'Зведення ніг у тренажері', array['adductors'], 27),
  ('calf_raise', 'Calf Raise', 'Підйом на носки', array['calves'], 28),
  ('shoulder_press', 'Shoulder Press', 'Жим над головою', array['shoulders','triceps'], 29),
  ('lateral_raise', 'Lateral Raise', 'Підйоми гантелей через сторони', array['shoulders'], 30),
  ('machine_lateral_raise', 'Machine Lateral Raise', 'Підйоми рук через сторони у тренажері', array['shoulders'], 31),
  ('rear_delt_fly', 'Rear Delt Fly', 'Зворотні розведення у тренажері', array['shoulders','upperBack'], 32),
  ('upright_row', 'Upright Row', 'Тяга штанги до підборіддя', array['shoulders','upperBack','biceps'], 33),
  ('biceps_curl', 'Biceps Curl', 'Згинання рук на біцепс', array['biceps','forearms'], 34),
  ('barbell_curl', 'Barbell Curl', 'Згинання рук зі штангою', array['biceps','forearms'], 35),
  ('seated_dumbbell_curl', 'Seated Dumbbell Curl', 'Згинання рук з гантелями сидячи', array['biceps','forearms'], 36),
  ('hammer_curl', 'Hammer Curl', 'Молоткові згинання рук', array['biceps','forearms'], 37),
  ('cable_curl', 'Cable Curl', 'Згинання рук на нижньому блоці', array['biceps','forearms'], 38),
  ('preacher_curl', 'Preacher Curl', 'Згинання рук на лаві Скотта', array['biceps','forearms'], 39),
  ('triceps_pushdown', 'Triceps Pushdown', 'Розгинання рук на блоці', array['triceps'], 40),
  ('v_bar_pushdown', 'V-Bar Triceps Pushdown', 'Розгинання рук на блоці з V-рукояттю', array['triceps'], 41),
  ('overhead_dumbbell_triceps_extension', 'Overhead Dumbbell Triceps Extension', 'Розгинання гантелі над головою', array['triceps','shoulders'], 42),
  ('french_press', 'French Press', 'Французький жим', array['triceps','shoulders'], 43),
  ('hyperextension', 'Hyperextension', 'Гіперекстензія', array['lowerBack','glutes','hamstrings'], 44),
  ('side_hyperextension', 'Side Hyperextension', 'Бокові нахили на гіперекстензії', array['obliques','abs','lowerBack'], 45),
  ('plank', 'Plank', 'Планка', array['abs','obliques'], 46),
  ('weighted_crunch', 'Weighted Crunch', 'Скручування з диском', array['abs','obliques'], 47),
  ('hanging_leg_raise', 'Hanging Leg Raise', 'Підйом ніг у висі', array['abs'], 48),
  ('plate_twist', 'Plate Twist', 'Повороти корпусу з диском', array['obliques','abs'], 49),
  ('weighted_side_bend', 'Weighted Side Bend', 'Бокові нахили з обтяженням', array['obliques','abs'], 50),
  ('warm_up', 'Warm Up', 'Розминка', array['shoulders','chest','upperBack','lats','abs','glutes','quads','hamstrings'], 51);

comment on table public.exercise_catalog is
  'Read-only bilingual exercise catalog embedded by GymApp clients for offline parity.';
