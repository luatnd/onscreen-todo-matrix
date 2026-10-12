# onscreen-todo-matrix: Idea v1.0.0

**Date:** 2026-10-12

## Problem
The owner manages work in Jira Cloud and already has a Jira dashboard for prioritization, but its UI does not show at a glance what matters. Arranging and reading tasks there is slow.

## Idea
A macOS desktop app with a floating panel, toggled by a global hotkey, that displays Jira issues as points in a 3D space instead of a 2D matrix:

- **Ox = Value / importance**
- **Oy = Effort / time**
- **Oz = Urgency**

This combines the **Eisenhower matrix** (urgent × important) with the **Action Priority matrix** (value × effort).

## Goals
With a quick look (~2 seconds), answer:
1. What should I do next?
2. What is on fire?
3. What is the overall shape of my workload?

## Key properties
- Open source, single user, personal use; all data local, no server.
- Jira Cloud; the user maps any Jira field (and its values) to each axis, e.g. Priority → urgency.
- One-way data: Jira → app. To change a task, open it in Jira from the panel, edit, and the app refetches.

## Status
Design approved in brainstorming on 2026-10-12. See [specs/arch-20261012-onscreen-todo-matrix-design.md](specs/arch-20261012-onscreen-todo-matrix-design.md).
