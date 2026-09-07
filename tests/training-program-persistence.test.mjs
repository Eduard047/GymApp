import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const source = fs.readFileSync(new URL('../pwa/app.js', import.meta.url), 'utf8');
const start = source.indexOf('function trainingProgramDescriptor(');
const end = source.indexOf('\nfunction ', source.indexOf('function updateTrainingProgramAction(', start) + 1);
function fixture() {
  const disk = new Map();
  const context = {
    TextEncoder, Date, console,
    TRAINING_PROGRAM_PREFIX: 'program:', activeAccount: { id: 'first' },
    activeWorkoutAccountDescriptor: account => ({ owner: account.id }),
    normalizeStoredAccount: account => account,
    sharedActiveAccountMatches: () => true,
    window: { GymStateContract: { LIMITS: { timestampMin: -62135769600000, timestampMax: 64092211200000 } } },
    localDateInputValue: timestamp => new Date(timestamp).toISOString().slice(0, 10),
    isWorkoutTimestampAllowed: timestamp => timestamp > 0 && timestamp <= Date.now(),
    clamp: (value, min, max) => Math.min(max, Math.max(min, value)),
    state: { profile: { days: 3, goal: 'strength' }, sessions: [] },
    modal: null, render() {},
    localStorage: { getItem: key => disk.get(key) ?? null, setItem: (key, value) => disk.set(key, value) }
  };
  vm.createContext(context);
  vm.runInContext(source.slice(start, end), context);
  return { context, disk };
}

test('program quota failure keeps committed schedule visible and retry restores writes', () => {
  const { context: c, disk } = fixture();
  assert.equal(c.createTrainingProgram(), true);
  const before = disk.get('program:first');
  c.localStorage.setItem = () => { throw new Error('QuotaExceededError'); };
  c.updateTrainingProgramAction('training-program-state', { dataset: { status: 'paused' } });
  assert.equal(disk.get('program:first'), before);
  assert.equal(c.loadTrainingProgram().status, 'active');
  assert.equal(vm.runInContext('trainingProgramRead.error', c), true);
  c.localStorage.setItem = (key, value) => disk.set(key, value);
  c.loadTrainingProgram({ reload: true });
  c.updateTrainingProgramAction('training-program-state', { dataset: { status: 'paused' } });
  assert.equal(c.loadTrainingProgram().status, 'paused');
});

test('program write rejects stale disk state and retains newer durable data', () => {
  const { context: c, disk } = fixture();
  assert.equal(c.createTrainingProgram(), true);
  const stale = c.loadTrainingProgram();
  disk.set('program:first', JSON.stringify({ ...stale, status: 'paused' }));
  assert.equal(c.saveTrainingProgram({ ...stale, status: 'completed' }), false);
  assert.equal(JSON.parse(disk.get('program:first')).status, 'paused');
});

test('finish and replacement require confirmation tied to account, revision and program', () => {
  const { context: c, disk } = fixture();
  c.createTrainingProgram();
  const id = c.loadTrainingProgram().id;
  c.updateTrainingProgramAction('training-program-finish', { dataset: {} });
  assert.equal(c.loadTrainingProgram().status, 'active');
  c.updateTrainingProgramAction('training-program-confirm', { dataset: {} });
  assert.equal(c.loadTrainingProgram().status, 'completed');
  c.updateTrainingProgramAction('training-program-reopen', { dataset: {} });
  assert.equal(c.loadTrainingProgram().id, id);
  assert.equal(c.loadTrainingProgram().status, 'active');
  c.saveTrainingProgram({ ...c.loadTrainingProgram(), status: 'completed' });
  assert.equal(c.createTrainingProgram(), false);
  c.updateTrainingProgramAction('training-program-new', { dataset: {} });
  c.activeAccount = { id: 'second' };
  c.updateTrainingProgramAction('training-program-confirm', { dataset: {} });
  assert.equal(c.loadTrainingProgram(), null);
  assert.equal(JSON.parse(disk.get('program:first')).id, id);
  c.activeAccount = { id: 'first' };
  c.loadTrainingProgram();
  c.updateTrainingProgramAction('training-program-new', { dataset: {} });
  c.updateTrainingProgramAction('training-program-confirm', { dataset: {} });
  assert.notEqual(c.loadTrainingProgram().id, id);
});

test('unreadable programs never become an empty writable schedule', () => {
  const { context: c, disk } = fixture();
  disk.set('program:first', '{corrupt');
  assert.equal(c.loadTrainingProgram(), null);
  assert.equal(c.createTrainingProgram(), false);
  assert.equal(disk.get('program:first'), '{corrupt');
});
