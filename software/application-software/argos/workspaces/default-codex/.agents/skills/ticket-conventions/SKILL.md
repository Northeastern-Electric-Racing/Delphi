---
name: ticket-conventions
description: Argos specifics for tickets (repo, area labels, vocabulary, diagrams). Load before drafting or filing an Argos issue, alongside create-ticket.
---

# Argos ticket conventions

The shared rules are in the `create-ticket` skill; this adds only what is Argos's.

- Repo: Northeastern-Electric-Racing/Argos (base branch `develop`).
- Area labels: `frontend`, `backend`, `devops` (any combination).
- Vocabulary: use the workspace glossary's terms (`docs/CONTEXT.md`), and check the code for current names, which may have moved past it (e.g. Zenoh key expressions, not MQTT topics).
- Title example: "Add pagination to the run list".
- Diagrams: Mermaid where it fits. Show the change across the parts it touches (car, Siren, scylla-server, angular-client), before and after.
