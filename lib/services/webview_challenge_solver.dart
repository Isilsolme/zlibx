// STAGE 1 STUB — do NOT treat as the real solver.
//
// OpenlibExtended's WebviewChallengeSolver opens a visible WebView so the
// user can solve a Cloudflare challenge by hand, then re-reads the HTML.
// That integration (visible challenge page + headless WebView wiring) is
// Stage 3 work; Stage 1 verifies Anna search against mirrors that do not
// challenge, so the fallback is deliberately a no-op here.
//
// What the stub guarantees:
//  * `isSupported` is false, so AnnasArchieve's two `on NetworkError`
//    catch blocks skip the challenge path and rethrow the original error.
//  * `fetchHtmlAfterChallenge` exists with the same signature, so the
//    ported annas_archieve.dart compiles unchanged.
// TODO (Stage 3): replace this stub with the real WebviewChallengeSolver
// (visible challenge page) per the port plan §7.1/§8 Stage 3.
class WebviewChallengeSolver {
  /// Stage 1: no visible challenge solving — always false.
  static bool get isSupported => false;

  /// Stage 1: never called (guarded by [isSupported]); returns null.
  static Future<String?> fetchHtmlAfterChallenge(String url) async => null;
}
