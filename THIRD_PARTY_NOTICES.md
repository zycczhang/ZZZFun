# Third-party notices

## KazumiRules

ZZZFun reads rule files from [Predidit/KazumiRules](https://github.com/Predidit/KazumiRules) at runtime. The repository is distributed under the MIT License. The upstream license text is available at:

https://github.com/Predidit/KazumiRules/blob/main/LICENSE

## Kazumi (rule parsing layer)

ZZZFun vendors the rule parsing layer of [Predidit/Kazumi](https://github.com/Predidit/Kazumi) as the local package `packages/kazumi_rules`.

Kazumi is licensed under the **GNU General Public License v3.0**. The license text is included in this repository at [LICENSE](LICENSE). The vendored files are copied verbatim from upstream, with two mechanical patches applied by `tool/sync_kazumi_rules.ps1`:

1. `package:kazumi/` imports are rewritten to `package:kazumi_rules/`.
2. The `package:dio` import and unused `RuleCancelToken` typedef are removed from `services/plugin/rule_engine_models.dart`.

The exact upstream commit in use is recorded in [packages/kazumi_rules/UPSTREAM.md](packages/kazumi_rules/UPSTREAM.md).

Because ZZZFun includes this GPL-3.0 code, ZZZFun as a whole is distributed under the GNU General Public License v3.0. Corresponding source is this repository.

## Other dependencies

Dart and Flutter package licenses are listed in `pubspec.lock`; run `flutter pub deps` or consult each package on pub.dev.
