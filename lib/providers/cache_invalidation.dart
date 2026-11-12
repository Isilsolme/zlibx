import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/home_feed_cache.dart';
import 'books_provider.dart';
import 'home_feed_provider.dart';

/// Invalidate every provider that caches account-scoped data.
///
/// This used to be a six-line `ref.invalidate(...)` block hand-copied
/// into logout / switchAccount / domain-switch — and the copies had
/// already drifted: none of them cleared the per-book favorites family
/// or the download-history cover map, so after switching accounts the
/// detail page showed the previous account's cached hearts and covers.
/// Keep the list here so it can never drift again.
void invalidateAccountScopedProviders(Ref ref) {
  // Drop the warm home feed too: it is account-scoped and must never leak
  // from the previous account into the next cold start.
  unawaited(HomeFeedCache.clear());
  ref.invalidate(bookDetailsProvider);
  ref.invalidate(homeFeedProvider);
  ref.invalidate(downloadedBooksProvider);
  ref.invalidate(savedBooksProvider);
  // Family providers must be invalidated as a whole (no member arg):
  // each cached (bookId -> bool / cover) entry belongs to the old
  // account's storage.
  ref.invalidate(isBookFavoritedProvider);
  ref.invalidate(historyCoverProvider);
}
