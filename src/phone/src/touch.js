// Touch -> the chart's mouse/wheel handlers. One finger: rotate / tap to select / double-tap opens the issue. Two fingers: pinch zoom.
export function installTouch(cv) {
  const fire = (type, t, target = cv, extra = {}) =>
    target.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, clientX: t.clientX, clientY: t.clientY, button: 0, ...extra }));
  let mode = null, pinch = 0, lastTap = { t: 0, x: 0, y: 0 };
  const dist = (e) => Math.hypot(e.touches[0].clientX - e.touches[1].clientX, e.touches[0].clientY - e.touches[1].clientY);

  cv.addEventListener('touchstart', (e) => {
    e.preventDefault();
    if (e.touches.length === 2) {
      if (mode === 'drag') fire('mouseup', e.touches[0], document.body); // end the rotate without a click on the canvas
      mode = 'pinch'; pinch = dist(e); return;
    }
    mode = 'drag'; fire('mousedown', e.touches[0]);
  }, { passive: false });
  cv.addEventListener('touchmove', (e) => {
    e.preventDefault();
    if (mode === 'pinch' && e.touches.length === 2) {
      const d = dist(e);
      if (pinch > 0 && d > 0) cv.dispatchEvent(new WheelEvent('wheel', { bubbles: true, cancelable: true, deltaY: -Math.log(d / pinch) / 0.0015 }));
      pinch = d; return;
    }
    if (mode === 'drag') fire('mousemove', e.touches[0]);
  }, { passive: false });
  const end = (e) => {
    e.preventDefault();
    if (mode === 'drag') {
      const t = e.changedTouches[0];
      fire('mouseup', t);
      const now = Date.now();
      if (now - lastTap.t < 320 && Math.hypot(t.clientX - lastTap.x, t.clientY - lastTap.y) < 24) { fire('dblclick', t); lastTap = { t: 0, x: 0, y: 0 }; }
      else lastTap = { t: now, x: t.clientX, y: t.clientY };
    }
    if (e.touches.length === 0) mode = null;
  };
  cv.addEventListener('touchend', end, { passive: false });
  cv.addEventListener('touchcancel', (e) => { if (mode === 'drag') fire('mouseup', e.changedTouches[0], document.body); mode = null; });
}
