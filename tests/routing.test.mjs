import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../build/workspace-client.js', import.meta.url), 'utf8');
const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
const routeBody = source.split('async restoreSelection(workspaces, sessions) {')[1].split('\n\t\t\tasync initializeDefaultWorkspace')[0].replace(/\n\t\t\t}\s*$/, '');
const restore = new AsyncFunction('workspaces', 'sessions', 'location', 'creationFailureMessage', routeBody);

test('explicit B takes precedence over saved A; no blank session creation', async () => {
  const calls = [];
  const service = {
    lifetime: new AbortController(),
    replaceMain(...args) { calls.push(args); },
    selection: {getSnapshot() { throw Error('must not read saved A'); }},
    connectWorkspace() { throw Error('must not create a blank session'); }
  };
  await restore.call(service, {}, {}, {search:'?conversation=B'}, String);
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], 'B');
  assert.equal(calls[0][2], 'reveal');
});

test('unknown/unauthorized explicit target uses existing notice and does not fall back', async () => {
  const notices = [];
  const service = {
    lifetime: new AbortController(),
    replaceMain() { throw Error('sessions.retain: unknown session inaccessible'); },
    notify(notice) { notices.push(notice); },
    selection: {getSnapshot() { throw Error('must not fall back'); }}
  };
  await restore.call(service, {}, {}, {search:'?conversation=inaccessible'}, String);
  assert.equal(notices.length, 1);
  assert.equal(notices[0].kind, 'createFailed');
  assert.match(notices[0].message, /unknown session inaccessible/);
});

test('deep-link startup selection is not persisted into primary window selection', () => {
  assert.match(source, /has\('conversation'\) \? \{\} : \{ persist: \{ name: "dsh.sessions.current" \} \}/);
});
