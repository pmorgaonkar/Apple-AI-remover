# RemoveMacAI-Bash

A Bash-first implementation for disabling Apple Intelligence features and resetting selected Apple Intelligence model assets on macOS.

> **Experimental / advanced users:** this project uses Apple's private
> `UnifiedAssetFramework` (UAF) and macOS configuration-profile mechanisms.
> Private APIs and configuration keys can change without notice between macOS
> releases. Review the code and generated profile before using it on a primary
> Mac.

## Why this project exists

The original RemoveMacAI project is implemented primarily in Swift with a small
Objective-C UAF bridge. This project explores how much of that behavior can be
made transparent and auditable in Bash.

The design deliberately keeps the native portion very small:

```text
remove-mac-ai.sh
    |
    +-- configuration profile
    +-- feature restrictions
    +-- download overrides
    +-- dry-run / status / revert
    |
    +-- uaf-reset.m
            |
            +-- UnifiedAssetFramework
            +-- NSXPC
            +-- ResetAssetSets
```

Bash handles the policy and orchestration. Objective-C is used only for the
private UAF/XPC operation.

## Requirements

- macOS 27.x
- Apple silicon (`arm64`)
- `/usr/bin/plutil`
- `/usr/bin/profiles`
- Apple Clang (`clang`) for building the helper
- Administrator authorization when macOS requests profile approval/removal

The project intentionally refuses unsupported macOS versions rather than
guessing at Apple's private asset-service behavior.

## Before changing anything

Inspect the repository:

```bash
sed -n '1,260p' remove-mac-ai.sh
sed -n '1,260p' uaf-reset.m
```

Validate the platform:

```bash
./remove-mac-ai.sh status
```

Preview the operation:

```bash
./remove-mac-ai.sh off --dry-run
```

The dry-run does not install a profile or call UAF.

## Usage

List supported feature identifiers:

```bash
./remove-mac-ai.sh features
```

Show current state:

```bash
./remove-mac-ai.sh status
```

Preview:

```bash
./remove-mac-ai.sh off --dry-run
```

Apply:

```bash
./remove-mac-ai.sh off
```

Non-interactive confirmation:

```bash
./remove-mac-ai.sh off --yes
```

Keep one feature enabled:

```bash
./remove-mac-ai.sh off --keep siri
```

Multiple features can be retained by repeating `--keep`:

```bash
./remove-mac-ai.sh off --keep siri --keep writing-tools
```

Revert the configuration profile:

```bash
./remove-mac-ai.sh revert
```

## What it changes

The current catalog targets Apple Intelligence-related functionality including:

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
- Xcode predictive completion

The exact behavior depends on Apple's current macOS implementation.

## Model assets

The project does **not** blindly delete arbitrary directories under `/System`.

Instead, after profile installation, the native helper asks Apple's asset service
to reset selected asset sets through UAF:

```text
Operation = ResetAssetSets
AssetSets = [...]
```

This is intentional. Apple's asset layout is private and may change.

## Preventing re-download

The generated configuration profile sets MobileAsset download overrides for
the selected asset classes. The current implementation uses a loopback endpoint
on port 9:

```text
https://127.0.0.1:9/removemacai-blocked/
```

This is a configuration mechanism, not a network firewall.

## Generated profile

The script writes:

```text
~/Downloads/RemoveMacAI-Bash.mobileconfig
```

Before approving the profile, inspect it:

```bash
plutil -p ~/Downloads/RemoveMacAI-Bash.mobileconfig
```

The profile identifier is:

```text
io.github.omlahore.removemacai.bash
```

The profile is intended to be removable. `revert` removes that profile by
identifier.

## Security model

This project intentionally does not use:

```text
curl ... | bash
```

as its installation model.

Clone/download the repository, inspect the files, and execute the local script.

The native helper is compiled locally using Apple's Clang. No precompiled
binary is required.

### Important security limitations

1. The UAF framework is private Apple software.
2. The XPC service name and interfaces are undocumented/private.
3. Configuration-profile keys can change.
4. This repository has no authority from Apple.
5. A macOS update may make the tool partially or completely ineffective.
6. The project has not been independently security audited.

Do not treat the project as a security product.

## Recovery

If the operation completes but behavior is unexpected:

```bash
./remove-mac-ai.sh revert
```

Then reboot if macOS still shows stale feature state.

If the profile is visible in System Settings, it can also be removed there.

The project does not intentionally modify `/System` or disable System Integrity
Protection.

## Relationship to the upstream project

This repository is an independent Bash-first implementation inspired by the
public implementation and documented behavior of:

https://github.com/omlahore/RemoveMacAI

It is not the upstream project and is not affiliated with Apple.

## Development

Check shell syntax:

```bash
bash -n remove-mac-ai.sh
```

Compile the helper manually:

```bash
clang -O2 -fobjc-arc -framework Foundation   -o uaf-reset uaf-reset.m
```

Remove the generated local binary before committing:

```bash
rm -f uaf-reset
```

## Versioning

The project currently starts at `0.1.0` because the implementation is
experimental and has not yet established compatibility across multiple macOS
27 point releases.

## License

MIT. See [LICENSE](LICENSE).
