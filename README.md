# Gunshot Jailed Debug Build Kit

Target: Google Photos 7.92.0 on a non-jailbroken device.

## Install into your fork

1. Fork `tqmane/gunshot`.
2. Create branch `debug/jailed-overlay`.
3. Copy the files in this kit into the matching paths.
4. Apply `Jailed/Makefile.patch` to `Jailed/Makefile`.
5. Commit and push.
6. GitHub Actions should run `Build Gunshot Jailed Debug` automatically, or run it manually from Actions.
7. Download artifact `gotohp-tweak-jailed-debug`.
8. Extract `GunshotJailed.dylib` (or use the `.deb` if your Sideloadly flow accepts it).

The overlay intentionally displays only diagnostic state: bundle ID, executable, version, SSO hook installation/use state, and current lifecycle status. It does not display tokens, cookies, media, or passwords.

Keep Sideloadly's automatic Bundle ID mangling enabled. The current Gunshot jailed implementation is designed to account for the mangled bundle identifier at runtime.
