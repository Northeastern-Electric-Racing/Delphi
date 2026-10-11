---
name: ticket-conventions
description: Nero specifics for tickets (repo, area labels, vocabulary, diagrams). Load before drafting or filing a Nero issue, alongside app:create-ticket.
user-invocable: false
---

# Nero ticket conventions

The shared rules are in `app:create-ticket`; this adds only what is Nero's.

- Repo: Northeastern-Electric-Racing/Nero-2.0 (base branch `develop`).
- Area labels: `view`, `controller`, `model`, `devops` (any combination).
- Title example: "Add a lap timer to the pit screen".
- Diagrams (required on epics, optional on dev work): Mermaid where it fits. Show the change across the view, controller, and model layers it touches, before and after.
