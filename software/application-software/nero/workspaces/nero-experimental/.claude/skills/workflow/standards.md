# Standards

The repo's CLAUDE.md files, root and per folder, come first. These add to them.

- Never push, post, open or update PRs, or commit unless the user asks for that action. A recommendation is not permission.
- Build only what the done criteria need. Simple code that is easy to change beats clever code.
- No comments, except a short one explaining a non-obvious "why". A link to the source of copied code counts as a why.
- Delete dead code, unused functions, logs, and traces, including topics and properties left behind by a removal. Never silence warnings.
- Reuse existing components, controllers, and utils before building. Extract duplicated logic.
- No speculative abstraction and no globals.
- Use full, domain-accurate names. Prefer enums and maps over if-chains.
- C++: avoid `auto` unless needed. Use `std::optional` with `has_value()`.
- Every `Q_PROPERTY` has a `NOTIFY` signal. Register context properties and image providers before `loadFromModule`.
- Never touch QML objects from worker threads; emit signals. Don't hold a `QMutex` across `emit`.
- Button indices and topic names live in one shared header each. Subscribe to explicit topics, never `#`.
- QML: versionless imports, bind `Theme` properties directly, and use `Shape` over `Canvas`.
- Keep PR scope tight. Don't touch unrelated files. Suggest extras as follow-up tickets.
