// Original, dependency-free Client half. Native windows belong to the desktop adapter.
window.__ModuleLoader__.load({
  id: '@zxw219/dsh-conversation-window',
  factory() {
    const namespace = 'zxw219.conversationWindow';
    // Client locale registration is synchronous; no fetch or application-state subscription.
    const en = {
      openWindow: 'Open in new window',
      adapterRequired: 'This feature requires a compatible DSH desktop conversation-window adapter. A browser pop-up is not a replacement.',
      openFailed: 'Could not open the conversation window: {message}',
      unknownError: 'Unknown desktop error',
    };
    const zh = {
      openWindow: '在新窗口中打开',
      adapterRequired: '此功能需要兼容的 DSH 桌面对话窗口适配补丁；浏览器弹窗不能代替原生窗口。',
      openFailed: '无法打开对话窗口：{message}',
      unknownError: '未知桌面错误',
    };
    return {
      inject: ['contextMenus', 'locale'],
      apply(ctx) {
        const menus = ctx.contextMenus;
        ctx.effect(() => ctx.locale.register(namespace, { en, zh }), 'conversation window: locale');
        const t = ctx.locale.bind(namespace);
        let disposed = false;
        ctx.effect(() => {
          disposed = false;
          const unregister = menus.register({
            id: 'zxw219.conversation-window',
            target: 'session',
            order: 50,
            resolve: ({ sessionId }) => [{
              id: 'openWindow',
              label: t('openWindow'),
              // Capture this menu's target, never the active conversation or its route.
              async run() {
                if (disposed) return;
                const conversations = window.dshDesktop?.conversations;
                if (typeof conversations?.openWindow !== 'function') {
                  menus.notify(t('adapterRequired'));
                  return;
                }
                try {
                  await conversations.openWindow(sessionId);
                } catch (error) {
                  if (disposed) return;
                  const message = typeof error?.message === 'string' && error.message
                    ? error.message : t('unknownError');
                  menus.notify(t('openFailed', { message }));
                }
              },
            }],
          });
          return () => {
            disposed = true;
            unregister();
          };
        }, 'conversation window: context menu');
      },
    };
  },
});
