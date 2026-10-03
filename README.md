# Apple AI remover

Bash-first macOS utility for disabling Apple Intelligence-related controls, resetting selected Apple Intelligence model sets through Apple's private UnifiedAssetFramework (UAF), and preventing selected asset re-downloads with a configuration profile.

**This is an advanced, experimental utility.** Apple-private APIs and configuration-profile keys are undocumented and can change between macOS releases. Review the source before use.

## Requirements

- macOS 27.x
- Apple silicon (arm64)
- Apple Clang / Xcode Command Line Tools
- administrator approval for the system configuration profile

The project intentionally refuses unsupported macOS major versions.

## Architecture

The shell program owns the catalog, dependency closure, profile generation, state reporting, confirmation flow, and recovery.

The small Objective-C helper is the only component that talks to private Apple APIs:

- `UAFConfigurationManager`
- `UAFAutoAssetManager`
- `UAFXPCProxyServiceInterface`
- XPC service `com.apple.siri.uaf.subscription.service`

The helper validates every model-set name against an explicit allowlist and checks the live UAF asset type before reading bytes or issuing a reset.

## Usage

The safest first step is the self-test:

```bash
bash remove-mac-ai.sh selftest
```

List the supported feature IDs:

```bash
bash remove-mac-ai.sh features
```

Inspect current state:

```bash
bash remove-mac-ai.sh status
```

Preview changes without installing a profile or resetting models:

```bash
bash remove-mac-ai.sh off --dry-run
```

Apply:

```bash
bash remove-mac-ai.sh off
```

Non-interactive mode:

```bash
bash remove-mac-ai.sh off --yes
```

Keep selected features enabled:

```bash
bash remove-mac-ai.sh off --keep siri
bash remove-mac-ai.sh off --keep siri,writing-tools
```

Revert this project's configuration profile:

```bash
bash remove-mac-ai.sh revert
```

To use `./remove-mac-ai.sh` directly, run `chmod +x remove-mac-ai.sh`.

## Features

The catalog currently covers:

- Siri / Siri AI
- external intelligence integrations / ChatGPT
- Writing Tools
- Genmoji
- Image Playground
- Mail summaries and smart replies
- notification summaries
- Messages summaries
- Safari summaries
- Notes transcription summaries
- inline text predictions
- Spatial Photos
- Photos Clean Up
- Xcode predictive code completion

Model reset uses dependency closure: a model set is reset only when no kept feature depends on that set.

## Configuration profile

The profile is generated at:

`~/Downloads/Apple-AI-remover.mobileconfig`

Profile identifier:

`io.github.pmorgaonkar.apple-ai-remover`

Payload UUIDs are deterministic for their identifiers, matching the upstream project's stable-UUID design. The profile is removable and contains a forced preference marker used for state detection.

Selected MobileAsset download overrides point at:

`https://127.0.0.1:9/apple-ai-remover-blocked/`

This is a configuration mechanism, not a firewall.

## Model handling

The implementation does not delete arbitrary files under `/System`.

For each selected model set, the helper:

1. resolves the UAF asset set;
2. verifies the live `autoAssetType` against the catalog;
3. reports `downloadedFilesystemBytes` for status;
4. sends `ResetAssetSets` through the private XPC service.

Reset requests are made one set at a time so a failure on one set does not silently convert into an empty or broader reset request.

## Safety and recovery

The tool does not intentionally modify `/System` or disable SIP.

`off` refuses to proceed when either the old Bash implementation's profile or the upstream RemoveMacAI profile is already active. This avoids stacking conflicting forced preferences.

Removing the project's profile restores the user's normal preference scope. Re-downloading Apple Intelligence assets after reversion is expected when Apple features are used again.

## Testing

GitHub Actions runs on macOS and currently performs:

```text
bash -n remove-mac-ai.sh
bash -n build-helper.sh
Apple Clang build of uaf-reset.m
bash remove-mac-ai.sh selftest
```

The CI test environment can verify compilation and catalog/profile invariants; it cannot prove behavior against every macOS build or Apple service deployment. Functional validation of private UAF operations must be performed on an appropriate target Mac.

## Upstream reference

The implementation was developed by inspecting the public source of:

https://github.com/omlahore/RemoveMacAI

Reference revision:

`609503f1e2e71c139779da2e1f23b813a7fcafef`

This repository is an independent implementation and is not affiliated with Apple or the upstream project.

## License

MIT. See [LICENSE](LICENSE).
