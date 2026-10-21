# ratelimit-ada

[![CI](https://github.com/kokhlo/ratelimit-ada/actions/workflows/build-test.yml/badge.svg)](https://github.com/kokhlo/ratelimit-ada/actions/workflows/build-test.yml)
[![Release](https://img.shields.io/badge/release-ratelimit--0.1.0-blue)](https://github.com/kokhlo/ratelimit-ada/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Alire](https://img.shields.io/badge/alire-ratelimit-orange)](https://alire.ada.dev/crates/ratelimit.html)

Token bucket and fixed window rate limiters for Ada. No dependencies,
pure Ada 2012, deterministic under a caller-supplied clock — no sleeping
in tests, no hidden timers in production.

## Why

Every network-facing service eventually needs admission control: API
quotas, upstream protection, login throttling. Ada's ecosystem had no
dedicated rate-limiting crate (the Alire index covers JSON, TOML, YAML,
UUIDs — but nothing for throttling). `ratelimit` fills that gap with two
battle-standard policies in ~400 lines of SPARK-friendly Ada.

## Policies

| Package | Best for | Behaviour |
|---|---|---|
| `Rate_Limit.Token_Bucket` | Smooth average rate with bursts | Tokens accrue at `Rate`/s up to `Burst`; each allowed request consumes one |
| `Rate_Limit.Fixed_Window` | Hard per-window quotas | Up to `Limit` admissions per `Window_Length` seconds; counter resets at window edges (epoch-aligned) |

## Install

```bash
alr with ratelimit
```

Or add to your `alire.toml`:

```toml
[[depends-on]]
ratelimit = "~0.1.0"
```

## Usage

### Token bucket (10 req/s average, bursts of 20)

```ada
with Ada.Calendar;
with Rate_Limit.Token_Bucket;

procedure Demo is
   use Rate_Limit.Token_Bucket;
   Buckets : Map := Empty_Map;
   R       : Limiter_Result;
begin
   R := Check (Buckets, "client-1",
               Rate  => 10.0,   --  sustained requests per second
               Burst => 20.0,   --  bucket capacity (initial fill)
               Now   => Ada.Calendar.Clock);
   if R.Outcome = Allowed then
      null;  --  serve the request
   elsif R.Outcome = Denied then
      delay R.Retry_After;  --  or return 429 + Retry-After header
   end if;
end Demo;
```

### Fixed window (100 requests per 60 s)

```ada
with Ada.Calendar;
with Rate_Limit.Fixed_Window;

procedure Demo is
   use Rate_Limit.Fixed_Window;
   Windows : Map := Empty_Map;
   R       : Limiter_Result;
   --  Limit => 100 admissions per 60s window
begin
   R := Check (Windows, "client-1",
               Limit         => 100,
               Window_Length => 60.0,
               Now           => Ada.Calendar.Clock);
   if R.Outcome = Allowed then
      null;  --  serve
   end if;
end Demo;
```

### Thread safety

The `Map`s are plain `Ada.Containers` maps, not task-safe by themselves.
Guard a shared limiter with a protected object:

```ada
protected Limiter is
   function Check (Key : String) return Limiter_Result;
private
   Buckets : Token_Bucket.Map := Token_Bucket.Empty_Map;
end Limiter;

protected body Limiter is
   function Check (Key : String) return Limiter_Result is
     (Token_Bucket.Check (Buckets, Key, 10.0, 20.0, Ada.Calendar.Clock));
end Limiter;
```

## API

`Rate_Limit.Limiter_Result` (both policies return it):

| Field | Meaning |
|--- |--- |
| `Outcome` | `Allowed` / `Denied` / `Rejected` (bad parameters) |
| `Retry_After` | For `Denied`: seconds until a retry can succeed; `0.0` otherwise |

Invalid parameters (`Rate <= 0`, `Burst < 1`, `Window_Length <= 0`) and
backwards clocks return `Rejected` without touching limiter state.

Keys are case-insensitive (API-token ergonomics); `Forget` drops one
key's state, `Clear` drops everything.

## Building and testing

```bash
alr build                 # library
gprbuild -p -P ratelimit_tests.gpr   # tests
./bin/rate_limit_tests   # 45 assertions, exit code 1 on any failure
```

## Status

v0.1.0 — public API stable for 0.x. Plans for 0.2: sliding window
counter, `Duration`-free `Ada.Time` monotonic clock source, per-limiter
metrics counters.

## License

MIT — see [LICENSE](LICENSE).
