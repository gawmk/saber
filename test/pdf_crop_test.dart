import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/image/editor_image.dart';

void main() {
  group('PdfEditorImage cropRect', () {
    final pdfBytes = Uint8List.fromList([1, 2, 3]);
    const naturalSize = Size(595, 842);
    const cropRect = Rect.fromLTWH(10, 20, 300, 150);

    PdfEditorImage createImage({Rect? cropRect}) => PdfEditorImage(
      id: 1,
      assetCache: AssetCache(),
      pdfBytes: pdfBytes,
      pdfFile: null,
      pdfPage: 2,
      cropRect: cropRect,
      pageIndex: 0,
      pageSize: .infinite,
      onMoveImage: null,
      onDeleteImage: null,
      onMiscChange: null,
      dstRect: const Rect.fromLTWH(0, 0, 600, 300),
      naturalSize: naturalSize,
    );

    test('survives a json round trip', () {
      final json = createImage(cropRect: cropRect).toJson(OrderedAssetCache());
      final image = PdfEditorImage.fromJson(
        json,
        inlineAssets: [pdfBytes],
        sbnPath: '',
        assetCache: AssetCache(),
      );
      expect(image.cropRect, cropRect);
      expect(image.pdfPage, 2);
    });

    test('is omitted from json when null', () {
      final json = createImage().toJson(OrderedAssetCache());
      expect(json.containsKey('crop'), isFalse);
    });

    test('is kept by copy', () {
      expect(createImage(cropRect: cropRect).copy().cropRect, cropRect);
    });
  });

  group('PdfEditorImage.cropForPageRegion', () {
    test('scales a region into natural units', () {
      final result = PdfEditorImage.cropForPageRegion(
        region: const Rect.fromLTWH(100, 200, 500, 100),
        pageSize: const Size(1000, 2000),
        naturalSize: const Size(500, 1000),
        fit: .contain,
      );
      expect(result?.crop, const Rect.fromLTWH(50, 100, 250, 50));
      expect(result?.onPage, const Rect.fromLTWH(100, 200, 500, 100));
    });

    test('clips the region to the drawn background', () {
      final result = PdfEditorImage.cropForPageRegion(
        region: const Rect.fromLTWH(0, 0, 1000, 300),
        pageSize: const Size(1000, 1000),
        naturalSize: const Size(500, 1000),
        fit: .contain,
      );
      expect(result?.onPage, const Rect.fromLTWH(250, 0, 500, 300));
      expect(result?.crop, const Rect.fromLTWH(0, 0, 500, 300));
    });

    test('returns null outside the drawn background', () {
      final result = PdfEditorImage.cropForPageRegion(
        region: const Rect.fromLTWH(0, 0, 200, 200),
        pageSize: const Size(1000, 1000),
        naturalSize: const Size(500, 1000),
        fit: .contain,
      );
      expect(result, isNull);
    });
  });
}
