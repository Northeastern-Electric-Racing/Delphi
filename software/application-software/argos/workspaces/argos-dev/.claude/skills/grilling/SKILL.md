---
name: grilling
description: Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases.
---

Interview the user until you reach a shared understanding. Map it as a **design tree**: every decision branches into the decisions that hang off it.

Work in **rounds**. The **frontier** is every decision whose prerequisites are settled. Ask the whole frontier at once, numbered, each with your recommended answer, then wait:

```
❓ **Q1** - **<title>**: <question, with choices if any>

➡️ <your recommended answer>
```

Each round of answers moves the frontier outward; recompute it and ask the next round. A question that depends on another still open this round waits for a later one.

Facts are your job, decisions are the user's. Never ask for anything you can look up in `repos/argos/` or the workspace `docs/`: send a sub-agent, and ask the rest of the frontier while it works.

Done when the frontier is empty and nothing is silently assumed. Don't act until the user confirms you share an understanding.
