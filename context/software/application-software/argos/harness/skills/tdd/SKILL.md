---
name: tdd
description: Test-driven development with red-green-refactor loop. Use when user wants to build features or fix bugs using TDD, mentions "red-green-refactor", wants integration tests, or asks for test-first development.
---

Tests verify behavior through public interfaces, not implementation. A good test reads like a spec ("user can upload a CSV") and survives a refactor. If renaming an internal function breaks a test, it was testing implementation.

1. **Plan.** Confirm with the user the interface changes and which behaviors matter most (you can't test everything). Prefer small interfaces over deep implementations.
2. **Loop, one test at a time.** RED: write one failing test for the next behavior. GREEN: write the minimum code to pass it. Never write all the tests first: bulk tests check imagined behavior.
3. **Refactor** only while green: remove duplication, deepen modules, and run the tests after each step.

Mock only at system boundaries (network, time, external services), never your own collaborators.
