# Contributing

1. Open an issue describing the behavior change and its Apple platform scope.
2. Add or update a failing test before production behavior.
3. Run `swift test`, `./scripts/test-mac.sh`, and the iOS simulator build from the README. Do not open a DerivedData `Margin.app` as the daily copy.
4. Do not include copyrighted book excerpts beyond short test quotations you are authorized to share.
5. Do not add telemetry, cloud history, silent local-to-cloud fallback, or new data collection without an explicit design review.

Keep platform integrations thin. Translation behavior, validation, and storage contracts belong in the shared packages where they can be tested without launching a host app.
