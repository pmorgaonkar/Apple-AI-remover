# Contributing

Thanks for contributing.

## Before submitting a change

Run:

```bash
bash -n remove-mac-ai.sh
```

If you change the native helper, verify it compiles on the supported macOS
version:

```bash
clang -O2 -fobjc-arc -framework Foundation -o uaf-reset uaf-reset.m
```

Do not commit the compiled `uaf-reset` binary.

## Design principles

1. Prefer transparent shell commands over hidden behavior.
2. Do not modify `/System`.
3. Do not disable SIP.
4. Keep private Apple API usage isolated to the smallest possible component.
5. Preserve a dry-run path for operations that modify system configuration.
6. Preserve a reversible configuration profile.
7. Refuse unsupported macOS versions instead of guessing.
8. Document changes to private API assumptions.

## Pull requests

Describe:

- macOS version tested
- Apple Silicon model if relevant
- exact command tested
- whether the test was dry-run or applied
- whether `revert` was tested
- any changes to Apple-private interfaces
