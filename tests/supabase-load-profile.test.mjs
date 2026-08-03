import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const sql = await readFile(
  "supabase/migrations/20260803090000_add_machine_load_profiles_and_assisted_dip.sql",
  "utf8"
);

test("Supabase validates optional machine profiles on every changed user state", () => {
  assert.match(sql, /create or replace function gymapp_private\.validate_exercise_load_profiles\(p_state jsonb\)/i);
  assert.match(sql, /direction'\) is distinct from 'string'[\s\S]*higherIsHarder[\s\S]*lowerIsHarder/i);
  assert.match(sql, /jsonb_array_length\(profile_value->'allowedWeightsKg'\) not between 1 and 128/i);
  assert.match(sql, /numeric_weight < 0 or numeric_weight > 1000000/i);
  assert.match(sql, /numeric_weight <= previous_weight/i);
  assert.match(sql, /before insert or update of state on public\.user_states/i);
  assert.match(sql, /old\.state is distinct from new\.state/i);
});

test("Supabase catalog adds assisted dip without widening client privileges", () => {
  assert.match(sql, /'assisted_dip',[\s\S]*'Assisted Dip',[\s\S]*'Віджимання на брусах у гравітроні'/i);
  assert.match(sql, /array\['triceps', 'chest', 'shoulders'\]/i);
  assert.match(sql, /revoke all on function gymapp_private\.validate_exercise_load_profiles\(jsonb\)[\s\S]*from public, anon, authenticated/i);
  assert.doesNotMatch(sql, /grant\s+(?:insert|update|delete|all)/i);
});
