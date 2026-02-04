# Commit Instructions

Copy the commit message block below and use it when committing the recent changes.

You can paste it into your editor when running `git commit` or use `git commit -F` with a temporary file.

Suggested commit message:

```
feat(notification,p2p,settings): add NotificationService + P2P integration and settings

- Add `NotificationService` and `RoomSummary` model to batch and emit local notifications.
- Integrate notifications into `P2pSessionController` with batching and configurable scan cadence.
- Add settings UI and `SettingsController` for background scanning toggle and cadence persistence.
- Make `NotificationService` test-safe (defer platform init / no-op in tests) and inject test-safe service in test fakes.
- Bump `flutter_local_notifications` to ^20.0.0 and update API usage.
- Fix tests and test helpers so `flutter test` passes.
```

Example commands:

```bash
# Stage changes
git add .

# Commit using an editor (recommended for multi-line messages)
git commit

# Or commit with the message file (create a temporary file and use -F):
# echo "$(sed -n '1,200p' docs/COMMIT_INSTRUCTIONS.md)" > /tmp/COMMIT_MSG.txt
# git commit -F /tmp/COMMIT_MSG.txt

# Push
git push origin HEAD
```

If you want, I can create the commit and push it for you—tell me the branch name to use.