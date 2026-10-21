# Contributing to ratelimit-ada

Thanks for your interest! This crate follows the same conventions as
the rest of the kokhlo Ada crate family (redis-ada, backoff-ada, ...).

## Getting started

```bash
git clone https://github.com/kokhlo/ratelimit-ada
cd ratelimit-ada
alr build
gprbuild -p -P ratelimit_tests.gpr && ./bin/ratelimit-tests
```

You need [Alire](https://alire.ada.dev) (`alr`) 2.0+; it pulls GNAT and
gprbuild for you (`alr toolchain --select`).

## Rules

1. **Tests are mandatory.** Every behaviour change ships with test
   coverage in `test/ratelimit-tests.adb`. Tests must be deterministic:
   pass explicit `Ada.Calendar.Time` values; never sleep.
2. **No new dependencies.** The crate is pure Ada 2012 with zero
   `depends-on`; keep it that way.
3. **Style**: GNAT warnings-as-errors mindset — the test project builds
   with `-gnatwa`. Two-space indent for continuation lines, `--  `
   comments (double dash + two spaces), 80-column soft limit.
4. **Public API changes need a changelog + version bump** in
   `alire.toml`, `README.md` badge, and `src/ratelimit.ads` Version
   constant, in the same commit.
5. **Commit messages**: conventional one-liners
   (`fix(token-bucket): refill before consuming`, `docs: ...`).

## Pull requests

- Keep diffs small and focused; one logical change per PR.
- CI must be green: Linux + macOS × GNAT 13/14/16 matrix plus the
  `alr with --use` consumer check.
- The release workflow enforces that tag, `alire.toml` version and
  README badge agree — bump all three together.

## Reporting bugs

Open an issue with: the policy used (token bucket / fixed window),
parameter values (rate/burst or limit/window), expected vs observed
outcome, and GNAT version (`gnatls -v`).
