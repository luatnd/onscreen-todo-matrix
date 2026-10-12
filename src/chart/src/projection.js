export const DEFAULT_CAMERA = { D: 1.5, H: 0.55 };
export const FACTORY_VIEW = { yaw: -179.7, pitch: 33.9, zoom: 1 };

/** World: x = value, y = effort (depth), z = urgency (up). Yaw around vertical axis, then pitch. */
export function project(x, y, z, cam) {
  const px = x - 0.5, py = z * cam.H - 0.2, pz = y - 0.5;
  const a = (cam.yaw * Math.PI) / 180, b = (cam.pitch * Math.PI) / 180;
  const X = px * Math.cos(a) - pz * Math.sin(a);
  const Z1 = px * Math.sin(a) + pz * Math.cos(a);
  const Y = py * Math.cos(b) + Z1 * Math.sin(b);
  const Z = -py * Math.sin(b) + Z1 * Math.cos(b);
  const s = cam.D / (cam.D + Z);
  const f = cam.fit || { cx: 0, cy: 0, sc: 1 };
  return { x: f.cx + X * s * f.sc, y: f.cy - Y * s * f.sc, z: Z, s, rx: X * s, ry: -Y * s };
}

export const normalizeYaw = (a) => ((((a + 180) % 360) + 360) % 360) - 180;

export function clampView(yaw, pitch, def, free) {
  if (free) return { yaw, pitch: Math.max(-89, Math.min(89, pitch)) };
  return {
    yaw: Math.max(def.yaw - 18, Math.min(def.yaw + 18, yaw)),
    pitch: Math.max(def.pitch - 10, Math.min(def.pitch + 10, pitch)),
  };
}
