import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { test } from 'node:test';
import { conversationWindowUrl, createConversationWindows } from '../adapter/conversation-windows.mjs';

const fake = (fail = false) => {
  const windows = [];
  const calls = [];
  const manager = createConversationWindows({
    applicationUrl: 'dsh-app://app/', preload: 'trusted-preload',
    assertSender(event) { if (event !== 'trusted') throw Error('unowned'); },
    createWindow(preload, show, primary) {
      // primary=true keeps the main window's chrome variant; assert it is requested.
      assert.deepEqual([preload, show, primary], ['trusted-preload', false, true]);
      const w = new EventEmitter();
      w.fail = fail;
      w.webContents = {id: windows.length + 1};
      w.isDestroyed = () => !!w.destroyed;
      w.destroy = () => { w.destroyed = true; w.emit('closed'); };
      w.loadURL = async url => { w.url = url; if (w.fail) throw Error('load failed'); };
      w.show = () => calls.push('show');
      windows.push(w);
      return w;
    },
    attach(w) { calls.push('attach'); }
  });
  return { manager, windows, calls };
};

test('selected B becomes internal URL; active A is not input or mutated', async () => {
  const active = {id:'A'};
  const {manager, windows, calls} = fake();
  await manager.open('trusted', 'B');
  assert.equal(windows[0].url, 'dsh-app://app/?conversation=B');
  assert.equal(active.id, 'A');
  assert.deepEqual(calls, ['attach','show']);
});

test('reject invalid IDs before constructing windows; never accept arbitrary URLs', async () => {
  const {manager, windows} = fake();
  for (const id of ['', null, {}, '../x', 'https://evil.test', 'x?conversation=y', 'x'.repeat(513)]) {
    await assert.rejects(manager.open('trusted', id), /Invalid conversation ID/);
  }
  assert.equal(windows.length, 0);
  assert.equal(conversationWindowUrl('dsh-app://app/', 'session-123_abc'), 'dsh-app://app/?conversation=session-123_abc');
});

test('reject unowned renderer before constructing a window', async () => {
  const {manager, windows} = fake();
  await assert.rejects(manager.open('untrusted', 'B'), /unowned/);
  assert.equal(windows.length, 0);
});

test('closing one window removes only its ownership; other window remains', async () => {
  const {manager, windows} = fake();
  await manager.open('trusted', 'B');
  await manager.open('trusted', 'B');
  assert.equal(manager.owns(windows[0].webContents), true);
  assert.equal(manager.ownsId(1), true);
  windows[0].destroy();
  assert.equal(manager.ownsId(1), false);
  assert.equal(manager.ownsId(2), true);
  assert.equal(windows[1].destroyed, undefined);
});

test('failed load destroys and deregisters only the failed window', async () => {
  const {manager, windows} = fake(true);
  await assert.rejects(manager.open('trusted','B'), /load failed/);
  assert.equal(windows[0].destroyed, true);
  assert.equal(manager.owns(windows[0].webContents), false);
});
