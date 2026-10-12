# Standards

The repo's CLAUDE.md files, root and per folder, come first. These add to them.

- Never push, post, open or update PRs, or commit unless the user asks for that action. A recommendation is not permission.
- Build only what the done criteria need. Simple code that is easy to change beats clever code.
- No comments, except a short one explaining a non-obvious "why". A link to the source of copied code counts as a why.
- Delete dead code, unused functions, logs, and traces. Never silence warnings.
- Reuse existing components, utils, and PrimeNG services before building. Extract duplicated logic.
- No speculative abstraction and no globals. Use async only when it earns it.
- Use full, domain-accurate names. Prefer enums and maps over if-chains.
- Test first, one behavior at a time, through public interfaces. Mock only at system boundaries. Assert exact values, cover the negative case, and keep tests deterministic.
- Angular: `model()` for two-way binding and PrimeNG theme vars. Never use `ng-deep`.
- Rust: rename fields server side with serde.
- C++: avoid `auto` unless needed. Use `std::optional` with `has_value()`.
- No hardcoded ports.
- Keep PR scope tight. Suggest extras as follow-up tickets.
