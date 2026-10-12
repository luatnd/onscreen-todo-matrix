# Feature: 3D Priority Panel for Jira

**Date:** 2026-10-12
**Category:** Productivity / Desktop tool / Jira

---

## 1. Elevator pitch
Press one key and a small panel floats over whatever you're doing, showing every Jira task you own as a glowing dot in a 3D space. The brightest dots are what you should do now. Two seconds, and you know your next move.

## 2. Problem
- Jira boards and dashboards are lists and columns. They tell you *what exists*, not *what matters now*.
- Classic prioritization grids (Eisenhower: urgent × important; Action Priority: value × effort) each show only two dimensions, so one of them is always missing.
- Checking priorities means switching apps, opening a dashboard, and reading.

## 3. What it does
- **One key (⌥Space)** shows or hides a floating panel above all apps.
- **Three dimensions at once:** the floor is Value × Effort (Quick wins, Major projects, Fill-ins, Thankless); height is Urgency.
- **Color tells priority:** each task's color mixes red (urgency), green (ease) and blue (value). White means urgent, valuable and easy: do it now. Dark means not worth it.
- **Top 3 "do next"** tasks get gold numbered badges; **on-fire** tasks glow red.
- **Task titles** appear next to the dots, with the most important ones always labeled.
- **Your Jira, your rules:** pick which Jira field drives each axis (for example Priority → urgency, Story Points → effort) and what each value means.
- **Edit in Jira, see it move:** open a task in Jira with ⌘O, change it, come back, and the dot glides to its new place.

## 4. Who it's for
Engineers, tech leads and managers who live in Jira Cloud and want a constant, glanceable sense of priority without opening dashboards.

## 5. Why it's different
- A real third dimension, instead of picking between Eisenhower and Action Priority.
- Built for a glance, not for analysis: brightness = priority.
- Private by design: runs locally, no server, token stored in macOS Keychain, read-only access to Jira.
- Open source and free.
