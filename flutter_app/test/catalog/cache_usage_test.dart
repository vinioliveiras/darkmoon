import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:darkmoon/catalog/cache_usage.dart';

/// The disk caches had no ceiling at all until 2026-09-09. The author's
/// own install had reached 1.8 GB, most of it two preview resolutions
/// abandoned months earlier that nothing was ever going to read again.
///
/// So the two things worth guarding are: the sweep reclaims the abandoned
/// data first, and it never touches what is expensive to rebuild.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('darkmoon_cache'));
  tearDown(() => root.deleteSync(recursive: true));

  /// Writes [bytes] bytes at `darkmoon/<parts>`, modified [ageDays] ago.
  File write(List<String> parts, int bytes, {int ageDays = 0}) {
    final file = File(p.joinAll([root.path, 'darkmoon', ...parts]));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List.filled(bytes, 0));
    file.setLastModifiedSync(DateTime.now().subtract(Duration(days: ageDays)));
    return file;
  }

  int sizeOf(List<String> parts) {
    final f = File(p.joinAll([root.path, 'darkmoon', ...parts]));
    return f.existsSync() ? f.lengthSync() : 0;
  }

  group('measuring', () {
    test('a fresh install measures zero rather than failing', () {
      final usage = measureCacheUsage(root.path);
      expect(usage.total, 0);
      expect(usage[CacheCategory.previews], 0);
    });

    test('each category is counted under its own name', () {
      write(['previews', 'v5', '2048px', 'a.cache'], 1000);
      write(['camera_match', 'v5', 'a.cache'], 50);
      write(['previews', 'v5', 'native', 'a.cache'], 9000);
      write(['thumbnails-320', 'a.cache'], 300);
      write(['ai_enhance_cache', 'a.png'], 700);
      write(['colorize_cache', 'a.png'], 200);

      final usage = measureCacheUsage(root.path);
      expect(
        usage[CacheCategory.previews],
        1050,
        reason:
            'the camera-match measurements belong with the previews '
            'they were taken for',
      );
      expect(
        usage[CacheCategory.fullSources],
        9000,
        reason:
            'native/ lives under previews/ but is its own category — '
            'these are the megabyte-scale entries',
      );
      expect(usage[CacheCategory.thumbnails], 300);
      expect(usage[CacheCategory.aiResults], 900);
      expect(usage.total, 11250);
      expect(usage.evictable, 10050, reason: 'AI results are not evictable');
    });

    test('the catalog and presets are not counted', () {
      // They are the user's work, not derived data. Showing them in a
      // meter beside a limit would invite treating them as reclaimable.
      write(['presets', 'a.xmp'], 5000);
      write(['catalog.json'], 5000);
      expect(measureCacheUsage(root.path).total, 0);
    });
  });

  group('the sweep', () {
    test('does nothing while under the limit', () {
      write(['previews', 'v5', '2048px', 'a.cache'], 1000);
      expect(enforceCacheLimit(CacheLimitRequest(root.path, 5000)), 0);
      expect(sizeOf(['previews', 'v5', '2048px', 'a.cache']), 1000);
    });

    test('takes the abandoned resolution before the one in use', () {
      // The whole reason this exists. Changing Settings > Preview
      // Resolution starts a new directory and abandons the old one;
      // nothing touches it again, so its files are the oldest in the tree.
      write(['previews', 'v5', '1024px', 'old.cache'], 1000, ageDays: 90);
      write(['previews', 'v5', '3072px', 'current.cache'], 1000);

      final freed = enforceCacheLimit(CacheLimitRequest(root.path, 1000));
      expect(freed, 1000);
      expect(sizeOf(['previews', 'v5', '1024px', 'old.cache']), 0);
      expect(
        sizeOf(['previews', 'v5', '3072px', 'current.cache']),
        1000,
        reason: 'the resolution actually in use must survive',
      );
    });

    test('never touches AI results, however far over the limit', () {
      // Rebuilding a preview costs a decode; rebuilding a colorized frame
      // costs minutes of inference. Reclaiming disk by throwing that away
      // is not a trade to make on the user's behalf.
      write(['ai_enhance_cache', 'a.png'], 9000, ageDays: 365);
      write(['colorize_cache', 'a.png'], 9000, ageDays: 365);
      write(['previews', 'v5', '2048px', 'a.cache'], 100);

      enforceCacheLimit(CacheLimitRequest(root.path, 0));
      expect(sizeOf(['ai_enhance_cache', 'a.png']), 9000);
      expect(sizeOf(['colorize_cache', 'a.png']), 9000);
      expect(sizeOf(['previews', 'v5', '2048px', 'a.cache']), 0);
    });

    test('leaves thumbnails alone too', () {
      // Small, and the filmstrip is unusable without them.
      write(['thumbnails-320', 'a.cache'], 9000, ageDays: 365);
      enforceCacheLimit(CacheLimitRequest(root.path, 0));
      expect(sizeOf(['thumbnails-320', 'a.cache']), 9000);
    });

    test('stops as soon as it fits, rather than emptying the cache', () {
      for (var i = 0; i < 5; i++) {
        write(['previews', 'v5', '2048px', '$i.cache'], 100, ageDays: 10 - i);
      }
      expect(enforceCacheLimit(CacheLimitRequest(root.path, 300)), 200);
      expect(measureCacheUsage(root.path).evictable, 300);
    });

    test('a missing cache tree is not an error', () {
      expect(enforceCacheLimit(CacheLimitRequest(root.path, 100)), 0);
    });
  });

  group('empty directories', () {
    test('an emptied resolution folder is removed', () {
      write(['previews', 'v5', '1024px', 'old.cache'], 1000, ageDays: 90);
      enforceCacheLimit(CacheLimitRequest(root.path, 0));
      removeEmptyCacheDirs(root.path);
      expect(
        Directory(
          p.join(root.path, 'darkmoon', 'previews', 'v5', '1024px'),
        ).existsSync(),
        isFalse,
        reason:
            'an abandoned resolution should not linger as an empty '
            'folder once its contents are gone',
      );
    });

    test('a folder that still holds something is left alone', () {
      write(['previews', 'v5', '3072px', 'a.cache'], 10);
      removeEmptyCacheDirs(root.path);
      expect(sizeOf(['previews', 'v5', '3072px', 'a.cache']), 10);
    });
  });

  group('clearing on request', () {
    test('one category goes and the others stay', () {
      write(['previews', 'v5', '2048px', 'a.cache'], 100);
      write(['previews', 'v5', 'native', 'a.cache'], 200);
      write(['thumbnails-320', 'a.cache'], 300);
      write(['ai_enhance_cache', 'a.png'], 400);

      final freed = clearCacheCategories(
        ClearCacheRequest.of(root.path, {CacheCategory.previews}),
      );
      expect(freed, 100);
      expect(sizeOf(['previews', 'v5', '2048px', 'a.cache']), 0);
      expect(
        sizeOf(['previews', 'v5', 'native', 'a.cache']),
        200,
        reason:
            'full-resolution sources live under previews/ but are a '
            'category of their own',
      );
      expect(sizeOf(['thumbnails-320', 'a.cache']), 300);
      expect(sizeOf(['ai_enhance_cache', 'a.png']), 400);
    });

    test('the camera matches go with the previews they belong to', () {
      write(['camera_match', 'v5', 'a.cache'], 50);
      clearCacheCategories(
        ClearCacheRequest.of(root.path, {CacheCategory.previews}),
      );
      expect(sizeOf(['camera_match', 'v5', 'a.cache']), 0);
    });

    test('asked directly, it does clear the AI results', () {
      // The automatic sweep never touches these — see the sweep's tests.
      // A person asking for the space back is a different thing, and
      // refusing would only mean they delete the folder by hand.
      write(['ai_enhance_cache', 'a.png'], 400);
      write(['ai_mask_cache', 'b.png'], 500);
      write(['colorize_cache', 'c.png'], 600);
      final freed = clearCacheCategories(
        ClearCacheRequest.of(root.path, {CacheCategory.aiResults}),
      );
      expect(freed, 1500);
      expect(measureCacheUsage(root.path)[CacheCategory.aiResults], 0);
    });

    test('every category at once empties the lot', () {
      write(['previews', 'v5', '2048px', 'a.cache'], 100);
      write(['previews', 'v5', 'native', 'a.cache'], 200);
      write(['thumbnails-320', 'a.cache'], 300);
      write(['colorize_cache', 'a.png'], 400);
      write(['presets', 'mine.xmp'], 999);

      clearCacheCategories(
        ClearCacheRequest.of(root.path, CacheCategory.values.toSet()),
      );
      expect(measureCacheUsage(root.path).total, 0);
      expect(
        sizeOf(['presets', 'mine.xmp']),
        999,
        reason: 'work the user made is not a cache and is never in scope',
      );
    });

    test('clearing nothing deletes nothing', () {
      write(['previews', 'v5', '2048px', 'a.cache'], 100);
      expect(clearCacheCategories(ClearCacheRequest.of(root.path, {})), 0);
      expect(sizeOf(['previews', 'v5', '2048px', 'a.cache']), 100);
    });
  });

  group('formatting', () {
    test('it reads the way a storage meter reads', () {
      expect(formatCacheBytes(0), '0 B');
      expect(formatCacheBytes(512), '512 B');
      expect(formatCacheBytes(1024), '1.0 KB');
      expect(formatCacheBytes(1536), '1.5 KB');
      // One decimal below ten, none above: 1.8 GB is worth the digit,
      // 412.3 MB is not.
      expect(formatCacheBytes(5 * 1024 * 1024 * 1024), '5.0 GB');
      expect(formatCacheBytes(412 * 1024 * 1024), '412 MB');
      expect(formatCacheBytes(20 * 1024 * 1024 * 1024), '20 GB');
    });

    test('it uses the same units the operating system reports', () {
      // Binary, so the number here and the number in the file manager
      // agree — a meter that disagrees with Explorer reads as a bug.
      expect(formatCacheBytes(1000), '1000 B');
      expect(formatCacheBytes(1024 * 1024), '1.0 MB');
    });
  });
}
