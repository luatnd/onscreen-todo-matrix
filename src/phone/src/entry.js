import { onMessage } from './shim.js';
import '../../chart/src/main.js';
import { installTouch } from './touch.js';
import { createApp } from './app.js';
import { createJira } from './jira.js';
import * as vault from './vault.js';

const $ = (id) => document.getElementById(id);
const show = (id, on) => { $(id).hidden = !on; };

const ui = {
  hide() { ['imp', 'impToken', 'impEmpty', 'impSettings'].forEach((i) => show(i, false)); show('gate', false); },
  showCode(err, fatal) {
    show('gate', true); ['impToken', 'impEmpty', 'impSettings'].forEach((i) => show(i, false)); show('imp', true);
    $('codeErr').textContent = err || ''; $('code').value = ''; $('code').disabled = !!fatal; $('codeGo').disabled = !!fatal;
    if (!fatal) $('code').focus();
  },
  showToken(email, err) {
    show('gate', true); ['imp', 'impEmpty', 'impSettings'].forEach((i) => show(i, false)); show('impToken', true);
    $('tokEmail').textContent = email; $('tokErr').textContent = err || ''; $('tok').value = ''; $('tok').focus();
  },
  showEmpty() { show('gate', true); ['imp', 'impToken', 'impSettings'].forEach((i) => show(i, false)); show('impEmpty', true); },
  showSettings() { show('gate', true); ['imp', 'impToken', 'impEmpty'].forEach((i) => show(i, false)); show('impSettings', true); },
};

const app = createApp({
  vault, ui, makeJira: ({ email, token }) => createJira({ email, token }),
  render: (s) => window.otm.render(s),
  openUrl: (u) => window.open(u, '_blank', 'noopener,noreferrer'),
});

// the fragment holds the encrypted settings: take it out of the address bar and history immediately
const hash = location.hash;
if (hash) history.replaceState(null, '', location.pathname + location.search);

$('codeGo').onclick = () => app.submitCode($('code').value);
$('code').onkeydown = (e) => { if (e.key === 'Enter') app.submitCode($('code').value); };
$('tokGo').onclick = () => app.submitToken($('tok').value);
$('tok').onkeydown = (e) => { if (e.key === 'Enter') app.submitToken($('tok').value); };
$('setClose').onclick = () => (app.session ? ui.hide() : ui.showEmpty());
$('setToken').onclick = () => app.reenterToken();
$('setForget').onclick = async () => {
  if (!confirm('Forget this phone? Settings, token and saved data are deleted from this device.')) return;
  await app.forget();
  if ('caches' in window) (await caches.keys()).forEach((k) => caches.delete(k));
  if (navigator.serviceWorker) (await navigator.serviceWorker.getRegistrations()).forEach((r) => r.unregister());
};

installTouch($('cv'));
onMessage((m) => { if (m.type === 'ready') app.boot(hash); else app.handle(m); });

// auto refresh while visible; refresh on return
let last = Date.now();
const every = () => ((app.session && app.session.config.quick.refreshMinutes) || 0) * 60000;
setInterval(() => { const e = every(); if (e && !document.hidden && Date.now() - last >= e) { last = Date.now(); app.refresh(); } }, 15000);
document.addEventListener('visibilitychange', () => { if (!document.hidden && every() && Date.now() - last > 60000) { last = Date.now(); app.refresh(); } });

if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
