# olib_api_plugin (rewrite)

Z-Library eapi client + data models for zlibx, rewritten from the
call sites in the app (inventory: `~/workspace/olib-plugin-call-inventory.md`).
It replaces the private upstream plugin, which the public repo never
shipped: `pubspec.yaml` references this package as `path: vendor/olib_api_plugin`.

Exports only what the app imports: `ZLibraryApi`, `Book`, `User`,
`ApiResponse<T>`.

> **兼容实现，与原作者无关。** Independent compatibility implementation,
> not affiliated with or endorsed by the original Olib author, and not the
> official plugin. Written from the public app's call sites only; it
> contains no code from the private upstream plugin, which was never
> published.

## Interface contract (from call sites, verified by grep)

- `ZLibraryApi()` — no-arg constructor; default domain `bookroom.lifestyle`
  (the app's `defaultDomain`). `setDomain(String)` switches the mirror.
- Auth: `login(email, password)`, `loginWithToken(userId, userKey)`,
  `sendCode(email, password, name)`, `verifyCode(email, password, name, code)`,
  `getProfile()`. Session = `remix_userid` / `remix_userkey` cookies.
- Search: `search({message, yearFrom, yearTo, languages, extensions,
  order, page, limit})` — POST form, repeated keys for list values.
  `ApiResponse.meta['total_pages']` drives pagination.
- Lists: `getBookInfo(bookId, hashId)`, `getMostPopular()`,
  `getUserRecommended()`, `getRecently()`, `getUserSaved({page, limit})`,
  `getUserDownloaded({limit})`, `saveBook(bookId)`, `unsaveUserBook(bookId)`,
  `similar(bookId, hashId)`.
- Download: `downloadBook(bookId, hash, savePath, {onProgress, cancelToken})`
  — Dio `CancelToken`, `(received, total)` progress, throws on failure.
- Error contract: `error == 'cf_blocked'` for Cloudflare walls, and
  timeout/socket/connection substrings for transient failures — the app's
  auth code branches on exactly those strings.

## Endpoint verification status

| Method | Endpoint used | Status |
|---|---|---|
| login | POST `/eapi/user/login` (+ website-login fields; falls back to POST `/rpc.php` on the same mirror if eapi login fails) | Eapi shape confirmed by independent public eapi clients (incl. heartleo/zlib, email+password only); the extra fields + rpc fallback were added 2026-11-05 after the app's community mirrors answered email+password-only with HTTP 400 on every line while the original app logs in — NOT yet live-verified |
| loginWithToken / getProfile | GET `/eapi/user/profile` | Confirmed (also named in the app's own auth comment) |
| search | POST `/eapi/book/search` | Confirmed, same parameter names |
| getBookInfo | GET `/eapi/book/{id}/{hash}` | Confirmed |
| downloadBook | GET `/eapi/book/{id}/{hash}/file` then stream the returned link | Confirmed |
| getUserSaved | GET `/eapi/user/book/saved` | Confirmed |
| unsaveUserBook | GET `/eapi/user/book/{id}/unsave` | Confirmed |
| getUserDownloaded | GET `/eapi/user/book/downloaded` | Confirmed by parameter shape in public clients |
| saveBook | GET `/eapi/user/book/{id}/save` | Inferred by symmetry with unsave |
| getMostPopular | GET `/eapi/book/most_popular`, fallback search `order=popular` on 404 | Inferred, fallback included |
| getUserRecommended | GET `/eapi/user/recommended`, fallback most-popular on 404 | Inferred, fallback included |
| getRecently | GET `/eapi/book/recently`, fallback search `order=newest` on 404 | Inferred, fallback included |
| similar | GET `/eapi/book/{id}/{hash}/similar`, fallback title search on 404 | Inferred, fallback included |
| sendCode / verifyCode | POST `/eapi/user/send_code`, `/eapi/user/verify_code` | Inferred, no fallback — registration is the least certain flow |

## What is NOT verified

No Flutter/Dart toolchain exists on this machine, and no Z-Library
account was used, so this package was written without being compiled,
analyzed, or run against a live mirror. It has since been compiled by CI
and exercised on device for the main flows (login, search, book detail);
the inferred rows above stay as marked until each is individually
confirmed. In particular:

- The inferred endpoints above may 404 or return a different JSON shape;
  the parsers accept camelCase/snake_case variants and several quota
  spellings to absorb shape differences, but they cannot invent an
  endpoint that does not exist.
- Cloudflare/DiamWall walls on some mirrors will still surface as
  `cf_blocked` (the app already handles that as "line unavailable").
- Response shapes for `Book` (cover URL form, `filesizeString`,
  `interestScore`) are best-effort mappings. `User.downloadsLeft` is
  `downloads_limit - downloads_today` from `/eapi/user/profile`
  (fallbacks `dailyDownloadLimit` / `dailyDownloadsCount`,
  `downloads_left`, a `limits` object); it is `null` when the payload
  carries no quota fields, and `null` must never be read as "exhausted"
  — a 0 default once made the app show the quota dialog before any
  download was even attempted (2026-11-05 device report).
- Download links: an absolute link from the `/file` response must be
  `https`; the session Cookie is sent only to the API's own domain
  (cross-domain links and redirect hops are fetched without it), and
  redirects are followed manually (max 5 hops) for the same reason.

The first live check (login → search → book info) has since passed on
device (2026-11-05); the remaining inferred rows are promoted only by
individual confirmation.

## Publishing note

`vendor/olib_api_plugin/` is tracked in this repo (the `vendor/` ignore
was removed when the rewrite landed). Interface shapes were cross-checked
against public third-party clients, including heartleo/zlib (MIT) — no
code, structure, or comments were taken from them; only the endpoint and
payload shapes were confirmed.
