// Conversation windows share the existing Desktop Host, never a second runner.
export function conversationWindowUrl(applicationUrl, sessionId) {
  if (typeof sessionId !== 'string' || sessionId.length === 0 || sessionId.length > 512 || !/^[A-Za-z0-9_-]+$/.test(sessionId)) {
    throw new Error('Invalid conversation ID');
  }
  const url = new URL(applicationUrl);
  url.searchParams.set('conversation', sessionId);
  return url.href;
}

export function createConversationWindows({ applicationUrl, createWindow, preload, attach, assertSender }) {
  const windows = new Set();
  return {
    owns(contents) {
      return [...windows].some(window => !window.isDestroyed() && window.webContents === contents);
    },
    ownsId(id) {
      return [...windows].some(window => !window.isDestroyed() && window.webContents.id === id);
    },
    async open(event, sessionId) {
      assertSender(event);
      const url = conversationWindowUrl(applicationUrl, sessionId);
      const window = createWindow(preload, false, false);
      windows.add(window);
      window.once('closed', () => windows.delete(window));
      try {
        attach(window);
        await window.loadURL(url);
        if (!window.isDestroyed()) window.show();
      } catch (error) {
        if (!window.isDestroyed()) window.destroy();
        throw error;
      }
    }
  };
}
