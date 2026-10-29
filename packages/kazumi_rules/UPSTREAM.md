# Vendored upstream

Source: https://github.com/Predidit/Kazumi (GPL-3.0)
commit: 87543b51fa0341299a235c47cf5c0c4bfef29818
ref: main
synced: 2026-10-29

Files under `lib/` are copied verbatim except for the two patches below, which
`tool/sync_kazumi_rules.ps1` applies on every run. Do not edit them by hand -
re-run the script instead.

1. `package:kazumi/` imports are rewritten to `package:kazumi_rules/`.
2. `services/plugin/rule_engine_models.dart`: the `package:dio` import and the
   `RuleCancelToken` typedef are removed. The dio-based request executor is not
   vendored; ZZZFun supplies its own in `lib/services/kazumi_api_rule_engine.dart`.

## Not vendored

These upstream files hold the rule-execution glue and depend on Dio, Dio
cookies, MobX, Hive or the app logger. ZZZFun reimplements the equivalent in
`lib/models/kazumi_rule_models.dart` and `lib/services/kazumi_api_rule_engine.dart`:

- `plugins/plugins.dart` — the `Plugin` class (config carrier + entry points)
- `services/plugin/rule_engine.dart` — Dio-backed orchestration
- `services/plugin/plugin_cookie_manager.dart`
- `services/plugin/api_rule_engine.dart` — barrel file for the above

## Re-syncing after an upstream change

    powershell -File tool/sync_kazumi_rules.ps1

The script aborts when upstream raises `ApiEndpoints.apiLevel`, because
`KazumiRule.supportedApiLevel` in `lib/models/kazumi_rule_models.dart` has to be
bumped by hand at the same time.

After a sync, refresh the fixtures and run the suite:

    dart run tool/fetch_kazumi_rule_fixtures.dart
    flutter test test/kazumi_rule_contract_test.dart

`test/kazumi_rule_contract_test.dart` fails when a published rule uses a feature
the vendored parser does not handle.
