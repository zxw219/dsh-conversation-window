import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import test from 'node:test';

const root = new URL('../', import.meta.url);
const source = await readFile(new URL('client.js', root), 'utf8');

function harness({ bridge, locale = 'en' } = {}) {
  let definition;
  let registration;
  let unregisters = 0;
  const notices = [];
  const effects = [];
  const dictionaries = new Map();
  const window = { dshDesktop: bridge, __ModuleLoader__: { load(value) { definition = value; } } };
  vm.runInNewContext(source, { window });
  assert.equal(definition.id, '@zxw219/dsh-conversation-window');
  const plugin = definition.factory();
  plugin.apply({
    // Deliberately unrelated main-window state: plugin must not read it.
    uiWorkspace: { get selection() { throw new Error('active selection accessed'); } },
    contextMenus: {
      register(value) { registration = value; return () => { unregisters++; }; },
      notify(value) { notices.push(value); },
    },
    locale: {
      register(namespace, value) { dictionaries.set(namespace, value); return () => dictionaries.delete(namespace); },
      bind(namespace) { return (key, args = {}) => Object.entries(args).reduce(
        (text, [name, value]) => text.replace(`{${name}}`, value), dictionaries.get(namespace)[locale][key]); },
    },
    effect(create) { effects.push(create()); },
  });
  return {
    window, notices, dictionaries,
    get registration() { return registration; },
    get unregisters() { return unregisters; },
    action(sessionId = 'B') { return registration.resolve({ sessionId })[0]; },
    dispose() { for (const cleanup of effects.reverse()) cleanup(); },
  };
}

test('captures right-click B rather than main-window A, invoking only native bridge', async () => {
  const calls = [];
  const h = harness({ bridge: { conversations: { async openWindow(id) { calls.push(id); } } } });
  assert.equal(h.registration.target, 'session');
  const action = h.action('B');
  h.action('C');
  await action.run();
  assert.deepEqual(calls, ['B']);
  assert.deepEqual(h.notices, []);
});

test('keeps action available without desktop bridge and explains the required adapter', async () => {
  const h = harness();
  assert.equal(h.action().label, 'Open in new window');
  await h.action().run();
  assert.match(h.notices[0], /requires a compatible DSH desktop/);
});

test('rejected bridge call uses existing context-menu error notification', async () => {
  const h = harness({ bridge: { conversations: { openWindow() { return Promise.reject(new Error('Access denied')); } } } });
  await h.action().run();
  assert.deepEqual(h.notices, ['Could not open the conversation window: Access denied']);
});

test('synchronous bridge failure and non-Error rejection do not escape', async () => {
  const h = harness({ bridge: { conversations: { openWindow() { throw null; } } } });
  await h.action().run();
  assert.match(h.notices[0], /Unknown desktop error/);
});

test('invalid ID passes only as an ID to adapter, and adapter failure is reported', async () => {
  const calls = [];
  const h = harness({ bridge: { conversations: { openWindow(id) { calls.push(id); throw new Error('Invalid conversation ID'); } } } });
  await h.action('../bad').run();
  assert.deepEqual(calls, ['../bad']);
  assert.match(h.notices[0], /Invalid conversation ID/);
});

test('Chinese locale and missing-bridge notification use registered dictionary', async () => {
  const h = harness({ locale: 'zh' });
  assert.equal(h.action().label, '在新窗口中打开');
  await h.action().run();
  assert.match(h.notices[0], /需要兼容的 DSH/);
});

test('dispose unregisters owned menu and dictionary; stale callbacks do nothing', async () => {
  let calls = 0;
  const h = harness({ bridge: { conversations: { async openWindow() { calls++; } } } });
  const action = h.action();
  h.dispose();
  await action.run();
  assert.equal(h.unregisters, 1);
  assert.equal(h.dictionaries.size, 0);
  assert.equal(calls, 0);
});

test('late rejected call after disposal cannot add a notice', async () => {
  let reject;
  const h = harness({ bridge: { conversations: { openWindow() { return new Promise((_, fail) => { reject = fail; }); } } } });
  const pending = h.action().run();
  h.dispose();
  reject(new Error('late failure'));
  await pending;
  assert.deepEqual(h.notices, []);
});

test('manifest and localized display resources export all required runtime files', async () => {
  const manifest = JSON.parse(await readFile(new URL('package.json', root), 'utf8'));
  assert.equal(manifest.exports['./client'], './client.js');
  assert.equal(manifest.dsh.client.immediately, true);
  for (const language of ['en', 'zh']) {
    const resource = JSON.parse(await readFile(new URL(`locale/${language}.json`, root), 'utf8'));
    assert.ok(resource.meta.title && resource.meta.description);
    assert.ok(resource.openWindow && resource.adapterRequired);
  }
  for (const file of ['index.js', 'client.js', 'cordis.patch.yml', 'icon.svg']) {
    assert.ok(manifest.files.includes(file));
    assert.ok((await readFile(new URL(file, root))).length > 0);
  }
});
