// Makes the unchanged chart believe it runs inside the Mac app: it posts to window.webkit.messageHandlers.otm.
// Messages are queued until the app registers its handler.
const queue = [];
let handler = null;
window.webkit = { messageHandlers: { otm: { postMessage: (m) => (handler ? handler(m) : queue.push(m)) } } };
export function onMessage(fn) { handler = fn; queue.splice(0).forEach(fn); }
