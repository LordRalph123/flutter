// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:test_api/src/expect/async_matcher.dart'; // ignore: implementation_imports
import 'package:test_api/test_api.dart'; // ignore: deprecated_member_use

import 'binding.dart';
import 'finders.dart';
import 'goldens.dart';

/// An unsupported method that exists for API compatibility.
Future<ui.Image> captureImage(Element element) {
  throw UnsupportedError('captureImage is not supported on the web.');
}

/// Whether or not [captureImage] is supported.
///
/// This can be used to skip tests on platforms that don't support
/// capturing images.
///
/// Currently this is true except when tests are running in the context of a web
/// browser (`flutter test --platform chrome`).
const bool canCaptureImage = false;

/// The matcher created by [matchesGoldenFile]. This class is enabled when the
/// test is running in a web browser using conditional import.
class MatchesGoldenFile extends AsyncMatcher {
  /// Creates an instance of [MatchesGoldenFile]. Called by [matchesGoldenFile].
  const MatchesGoldenFile(this.key, this.version);

  /// Creates an instance of [MatchesGoldenFile]. Called by [matchesGoldenFile].
  MatchesGoldenFile.forStringPath(String path, this.version) : key = Uri.parse(path);

  /// The [key] to the golden image.
  final Uri key;

  /// The [version] of the golden image.
  final int? version;

  @override
  Future<String?> matchAsync(dynamic item) async {
    if (item is! Finder) {
      return 'web goldens only supports matching finders.';
    }
    final Iterable<Element> elements = item.evaluate();
    if (elements.isEmpty) {
      return 'could not be rendered because no widget was found';
    } else if (elements.length > 1) {
      return 'matched too many widgets';
    }
    final Element element = elements.single;
    final RenderObject renderObject = _findRepaintBoundary(element);
    final Size size = renderObject.paintBounds.size;
    final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.instance;
    final Element e = binding.renderViewElement!;
    final ui.FlutterView view = binding.platformDispatcher.implicitView!;

    // Unlike `flutter_tester`, we don't have the ability to render an element
    // to an image directly. Instead, we will use `window.render()` to render
    // only the element being requested, and send a request to the test server
    // requesting it to take a screenshot through the browser's debug interface.
    _renderElement(view, renderObject);
    final String? result = await binding.runAsync<String?>(() async {
      if (autoUpdateGoldenFiles) {
        await webGoldenComparator.update(size.width, size.height, key);
        return null;
      }
      try {
        final bool success = await webGoldenComparator.compare(size.width, size.height, key);
        return success ? null : 'does not match';
      } on TestFailure catch (ex) {
        return ex.message;
      }
    }, additionalTime: const Duration(seconds: 22));
    _renderElement(view, _findRepaintBoundary(e));
    return result;
  }

  @override
  Description describe(Description description) {
    final Uri testNameUri = webGoldenComparator.getTestUri(key, version);
    return description.add('one widget whose rasterized image matches golden image "$testNameUri"');
  }
}

RenderObject _findRepaintBoundary(Element element) {
  assert(element.renderObject != null);
  RenderObject renderObject = element.renderObject!;
  while (!renderObject.isRepaintBoundary) {
    renderObject = renderObject.parent! as RenderObject;
  }
  return renderObject;
}

void _renderElement(ui.FlutterView window, RenderObject renderObject) {
  assert(renderObject.debugLayer != null);
  final Layer layer = renderObject.debugLayer!;
  final ui.SceneBuilder sceneBuilder = ui.SceneBuilder();
  if (layer is OffsetLayer) {
    sceneBuilder.pushOffset(-layer.offset.dx, -layer.offset.dy);
  }
  // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
  layer.updateSubtreeNeedsAddToScene();
  // ignore: invalid_use_of_protected_member
  layer.addToScene(sceneBuilder);
  sceneBuilder.pop();
  window.render(sceneBuilder.build());
}
