# Release checklist

- [ ] Update `VERSION`
- [ ] Update `CHANGELOG.md`
- [ ] Run `bash -n remove-mac-ai.sh`
- [ ] Run `./remove-mac-ai.sh status`
- [ ] Run `./remove-mac-ai.sh off --dry-run`
- [ ] Inspect generated `.mobileconfig`
- [ ] Compile `uaf-reset.m` on supported macOS
- [ ] Test profile installation
- [ ] Test UAF reset
- [ ] Test `revert`
- [ ] Remove compiled `uaf-reset` before commit
- [ ] Review `git diff`
- [ ] Tag release
