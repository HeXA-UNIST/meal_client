# AGENTS.md

This is a guardrail and routing file, not a codebase overview. Current source,
tests, and configuration are the source of truth. Verify task-relevant behavior
before editing and flag any conflict with this file.

## Project

밥먹어U (BapU) is a Flutter app for viewing UNIST cafeteria menus.
Supported platforms: Android, iOS, and Web.

## Before Editing

- Read the affected code path, nearby tests, and `git status`. Do not rely on
  remembered architecture or an older document snapshot.
- Preserve the user's worktree. Do not stash, reset, switch branches, stage,
  commit, delete, or tidy unrelated files unless explicitly asked.
- Make the smallest change that satisfies the request. Do not add features,
  refactor adjacent code, or introduce a new abstraction without a demonstrated
  need.
- Match the local design. Do not impose a repository pattern or stricter layer
  boundary merely because it is conventional elsewhere.
- Ask before making product, policy, compatibility, or Git-history decisions that
  cannot be resolved from current code and tests.
- Code comments and test descriptions are Korean.

## Routing

- Use `README.md` for current commands and the documentation index.
- Treat `pubspec.yaml`, `analysis_options.yaml`, and `l10n.yaml` as authoritative
  for SDK, dependency, analyzer, and localization configuration.
- Preserve existing conditional-export boundaries when changing platform code;
  keep Web paths free of `dart:io` and native-only imports.
- Use architecture documents for orientation only, then verify the relevant path
  in source. Search for symbols and user-visible text instead of relying on a
  fixed file or test list.
- Before changing `lib/features/home/nested_page_scroll.dart`, read its comments
  and `docs/features/nested_page_scroll.md`; its touch and pointer paths form a
  coupled state machine.

## Change-Sensitive Guardrails

### Localization

- Edit the Korean and English ARB files, never generated
  `lib/l10n/app_localizations*.dart` files directly.
- Keep locale keys aligned, run `flutter gen-l10n`, and update tests that assert
  localized text.

### Shared data and native consumers

- Before changing cache paths, names, schemas, freshness, parsing, or write order,
  trace Flutter foreground/background code plus Android, iOS, and bridge consumers.
- Preserve atomic final-file writes. On iOS, backup exclusion must be applied to
  the final file after rename, not only to a temporary file.
- Native widgets consume the shared cache. A new native network owner or a silent
  fixed-data fallback requires an explicit product decision.
- Cache-first display and fresh-response decisions are different concerns. Do not
  use cached info for a decision that requires current server data, such as
  detecting a newly published announcement.
- When renaming persisted settings or enums, trace storage keys, serialization,
  scheduling/filtering code, legacy values, and tests before deciding migration
  behavior.

### Notifications and lifecycle UI

- Trace notification changes through UI state, persistence, scheduling, delivery
  filtering, platform permission, and cleanup. Updating only the visible control
  is insufficient.
- App preference and OS authorization are distinct states; do not infer one from
  the other.
- Feedback after a system permission dialog must wait for a real Flutter frame.
  Guard deferred callbacks against disposal and remove screen-owned feedback when
  the route exits.

### UI changes

- Preserve exact requested labels, spacing, and behavior. Reuse the touched
  screen's local constants and theme typography; avoid global styling or unrelated
  visual cleanup.
- Prefer standard Material selected and disabled states. Add custom styling only
  for the requested distinction and preserve accessibility semantics.

## Validation

Validate in proportion to the change and report any unverified boundary.

- Documentation only: inspect the final diff and run `git diff --check`.
- Dart/Flutter: format changed Dart files, run the narrowest relevant tests, and
  run `flutter analyze` when the change can affect the application broadly.
- Create tests only when requirements or implementation are complex enough to
  warrant TDD, or when regression coverage is essential to preserve correct app
  behavior through future maintenance. Do not create tests for simple changes;
  run relevant existing tests instead.
- Localization: run generation, affected tests, and analysis.
- Platform code: run available platform tests or builds. On Windows, do not claim
  Xcode, WidgetKit, signing, VoiceOver, or iOS-device validation. Treat real-device
  notification timing and launcher-widget behavior as separate QA boundaries.
- Before handoff, review the diff for correctness, code quality, scope, and
  overengineering. If a commit was requested, also inspect the staged file list
  and run `git diff --cached --check` without including unrelated changes.

## Maintenance

Keep root guidance cross-cutting. Put a recurring module-specific landmine in the
nearest scoped `AGENTS.md` only when source and tests cannot make it obvious.
Remove rules when the underlying friction is fixed. Do not copy version numbers,
package inventories, directory trees, command catalogs, or TODO lists into this
file.
