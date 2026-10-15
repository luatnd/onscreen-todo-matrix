// Fictional "Acme" demo tasks for the README hero image. No real people, sites or issues.
// Values are 0..1 (effort 0 = trivial, 1 = huge). score / rank / fire are computed in demo.js.
const t = (key, summary, status, priority, due, value, effort, urgency, extra = {}) =>
  ({ key, summary, status, priority, due, value, effort, urgency, ...extra });

export const DEMO_TASKS = [
  // Quick wins: value >= .5, effort < .5
  t('SEC-5', 'Rotate leaked Stripe API key', 'In Progress', 'Highest', '2026-10-15', 0.95, 0.10, 1.0),
  t('PAY-412', 'Refund webhook returns 500 on partial refunds', 'To Do', 'Highest', null, 0.90, 0.25, 0.90,
    { derived: { kind: 'timeline', amount: 16, unit: 'h', from: '2026-10-14', to: '2026-10-15', clamped: false } }),
  t('WEB-140', 'Fix checkout button on Safari 17', 'In Review', 'High', '2026-10-17', 0.85, 0.15, 0.60),
  t('WEB-97', 'Compress hero images for faster LCP', 'To Do', 'Medium', null, 0.62, 0.12, 0.45),
  t('OPS-204', 'Alert on failed nightly backups', 'To Do', 'High', null, 0.70, 0.30, 0.55),
  t('MOB-61', 'Crash on launch with iOS 17.4', 'In Progress', 'High', '2026-10-18', 0.78, 0.35, 0.72),
  t('DATA-33', 'Fix timezone in daily revenue dashboard', 'To Do', 'Medium', null, 0.56, 0.38, 0.35),
  t('PAY-455', 'Show VAT line on receipts', 'To Do', 'High', '2026-10-20', 0.58, 0.22, 0.68),
  t('WEB-188', 'Add dark mode toggle to settings', 'Backlog', 'Low', null, 0.55, 0.42, 0.15),

  // Major projects: value >= .5, effort >= .5
  t('OPS-231', 'Migrate Postgres to 16, zero downtime', 'In Progress', 'Highest', '2026-10-16', 0.80, 0.70, 0.85),
  t('DATA-19', 'Rebuild data warehouse on ClickHouse', 'Backlog', null, null, 0.85, 0.50, 0.20, { missingEffort: true }),
  t('MOB-102', 'Offline mode for order history', 'To Do', 'Medium', null, 0.70, 0.50, 0.40, { missingEffort: true }),
  t('PAY-390', 'Support SEPA direct debit', 'To Do', 'Medium', null, 0.75, 0.80, 0.45),
  t('WEB-165', 'Rewrite onboarding flow in React', 'In Progress', 'Medium', null, 0.62, 0.72, 0.30,
    { derived: { kind: 'logged', amount: 24, unit: 'h', from: null, to: null, clamped: false } }),
  t('SEC-31', 'Pen-test fixes: session handling', 'To Do', 'High', null, 0.90, 0.62, 0.55),

  // Fill-ins: value < .5, effort < .5
  t('CORE-201', 'Update README badges', 'To Do', 'Low', null, 0.30, 0.15, 0.30),
  t('CORE-202', 'Remove unused CSS classes', 'To Do', 'Low', null, 0.30, 0.15, 0.30),
  t('CORE-203', 'Fix typos in API docs', 'To Do', 'Low', null, 0.30, 0.15, 0.30),
  t('HR-21', 'Book venue for team offsite', 'To Do', 'Medium', '2026-10-21', 0.35, 0.30, 0.65),
  t('OPS-188', 'Rotate staging logs weekly', 'Backlog', 'Low', null, 0.22, 0.40, 0.10),
  t('DATA-48', 'Archive stale Looker dashboards', 'In Review', 'Low', null, 0.42, 0.25, 0.22,
    { derived: { kind: 'timeline', amount: 8, unit: 'h', from: '2026-10-14', to: '2026-10-15', clamped: false } }),

  // Thankless: value < .5, effort >= .5
  t('HR-30', 'Annual compliance training', 'To Do', 'Medium', '2026-10-24', 0.25, 0.50, 0.70, { missingEffort: true }),
  t('DATA-60', 'Migrate legacy CSV exports', 'Backlog', 'Low', null, 0.35, 0.80, 0.28),
  t('MOB-140', 'Replace deprecated Android APIs', 'To Do', 'Medium', null, 0.42, 0.68, 0.45),
  t('WEB-230', 'Rewrite legacy jQuery widgets', 'Backlog', 'Low', null, 0.20, 0.90, 0.10),
];
