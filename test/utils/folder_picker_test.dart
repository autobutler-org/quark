import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/folder_picker.dart';

/// Compiling this file is half the point: it resolves the conditional import
/// to the dart:io side of the folder picker, so a break there fails the suite
/// instead of waiting for a desktop build.
void main() {
  test('desktop can pick a folder, mobile cannot', () {
    // Mobile is deliberately out of scope — Android returns protected paths
    // and iOS has no directory chooser at all, so the action is hidden there
    // rather than offered broken.
    final expected = Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    expect(isFolderPickerSupported, expected);
  });

  test('a separate Photos picker is only needed on iOS', () {
    expect(isPhotoLibraryPickerNeeded, Platform.isIOS);
  });

  test('the Photos accept filter is images and videos, not capture', () {
    expect(kPhotoUploadAccept, 'image/*,video/*');
    expect(kPhotoUploadAccept.contains('capture'), isFalse);
  });

  test('iPhone and iPad user agents need the Photos picker', () {
    expect(
      isIosPhotoLibraryClient(
        userAgent:
            'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 '
            'Mobile/15E148 Safari/604.1',
        platform: 'iPhone',
        maxTouchPoints: 5,
      ),
      isTrue,
    );
    expect(
      isIosPhotoLibraryClient(
        userAgent:
            'Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
            'Mobile/15E148 Safari/604.1',
        platform: 'iPad',
        maxTouchPoints: 5,
      ),
      isTrue,
    );
  });

  test('iPadOS desktop-mode Safari still needs the Photos picker', () {
    // iPadOS 13+ defaults to a Macintosh UA. Touch points are the tell.
    expect(
      isIosPhotoLibraryClient(
        userAgent:
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 '
            'Safari/605.1.15',
        platform: 'MacIntel',
        maxTouchPoints: 5,
      ),
      isTrue,
    );
  });

  test('a real Mac does not need a separate Photos picker', () {
    expect(
      isIosPhotoLibraryClient(
        userAgent:
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 '
            'Safari/605.1.15',
        platform: 'MacIntel',
        maxTouchPoints: 0,
      ),
      isFalse,
    );
  });

  test('Android Chrome does not need a separate Photos picker', () {
    expect(
      isIosPhotoLibraryClient(
        userAgent:
            'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36',
        platform: 'Linux armv8l',
        maxTouchPoints: 5,
      ),
      isFalse,
    );
  });
}
