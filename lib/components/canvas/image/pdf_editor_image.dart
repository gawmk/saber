part of 'editor_image.dart';

class PdfEditorImage extends EditorImage {
  Uint8List? pdfBytes;

  /// The index of the relevant page in the [_pdfDocument].
  /// The first page is 0.
  final int pdfPage;

  /// If the pdf needs to be loaded from disk, this is the File
  /// that the pdf will be loaded from.
  final File? pdfFile;

  /// The region of the pdf page to show, in the page's natural units
  /// (see [naturalSize]). If null, the whole page is shown.
  final Rect? cropRect;

  final _pdfDocument = ValueNotifier<PdfDocument?>(null);

  static final log = Logger('PdfEditorImage');

  new({
    required super.id,
    required super.assetCache,
    required this.pdfBytes,
    required this.pdfFile,
    required this.pdfPage,
    this.cropRect,
    required super.pageIndex,
    required super.pageSize,
    super.invertible,
    super.backgroundFit,
    required super.onMoveImage,
    required super.onDeleteImage,
    required super.onMiscChange,
    super.onLoad,
    super.newImage,
    super.dstRect,
    required super.naturalSize,
    super.isThumbnail,
  }) : assert(
         !naturalSize.isEmpty,
         'naturalSize must be set for PdfEditorImage',
       ),
       assert(
         pdfBytes != null || pdfFile != null,
         'pdfFile must be set if pdfBytes is null',
       ),
       super(extension: '.pdf', srcRect: .zero);

  factory fromJson(
    Map<String, dynamic> json, {
    required List<Uint8List>? inlineAssets,
    bool isThumbnail = false,
    required String sbnPath,
    required AssetCache assetCache,
  }) {
    final extension = json['e'] as String?;
    assert(extension == null || extension == '.pdf');

    final assetIndex = json['a'] as int?;
    final Uint8List? pdfBytes;
    File? pdfFile;
    if (assetIndex != null) {
      if (inlineAssets == null) {
        pdfFile = FileManager.getFile(
          '$sbnPath${Editor.extension}.$assetIndex',
        );
        pdfBytes = assetCache.get(pdfFile);
      } else {
        pdfBytes = inlineAssets[assetIndex];
      }
    } else {
      if (kDebugMode) {
        throw Exception('PdfEditorImage.fromJson: pdf bytes not found');
      }
      pdfBytes = Uint8List(0);
    }

    final crop = (json['crop'] as List?)?.cast<num>();

    int? pdfPage = json['pdfi'];
    if (pdfPage == null) {
      log.warning(
        'fromJson: missing pdfPage. '
        'This may have been caused by https://github.com/saber-notes/saber/issues/1689.',
      );
      pdfPage = 0;
    }

    return PdfEditorImage(
      id:
          json['id'] ??
          -1, // -1 will be replaced by EditorCoreInfo._handleEmptyImageIds()
      assetCache: assetCache,
      pdfBytes: pdfBytes,
      pdfFile: pdfFile,
      pdfPage: pdfPage,
      cropRect: crop == null
          ? null
          : .fromLTWH(
              crop[0].toDouble(),
              crop[1].toDouble(),
              crop[2].toDouble(),
              crop[3].toDouble(),
            ),
      pageIndex: json['i'] ?? 0,
      pageSize: .infinite,
      invertible: json['v'] ?? true,
      backgroundFit: json['f'] != null ? .values[json['f']] : .contain,
      onMoveImage: null,
      onDeleteImage: null,
      onMiscChange: null,
      onLoad: null,
      newImage: false,
      dstRect: .fromLTWH(
        json['x'] ?? 0,
        json['y'] ?? 0,
        json['w'] ?? 0,
        json['h'] ?? 0,
      ),
      naturalSize: Size(json['nw'] ?? 0, json['nh'] ?? 0),
      isThumbnail: isThumbnail,
    );
  }

  @override
  Map<String, dynamic> toJson(OrderedAssetCache assets) {
    final json = super.toJson(assets);
    assert(!json.containsKey('a'));

    json['a'] = pdfFile != null
        ? assets.addFile(pdfFile!)
        : assets.addBytes(pdfBytes!);
    json['pdfi'] = pdfPage;
    if (cropRect case final crop?) {
      json['crop'] = [crop.left, crop.top, crop.width, crop.height];
    }

    return json;
  }

  @override
  Future<void> firstLoad() async {
    assert(srcRect.isEmpty);
    assert(!naturalSize.isEmpty);

    if (dstRect.isEmpty) {
      final shownSize = cropRect?.size ?? naturalSize;
      final dstSize = pageSize != null
          ? EditorImage.resize(shownSize, pageSize!)
          : shownSize;
      dstRect = dstRect.topLeft & dstSize;
    }

    assert(id != -1, 'id must be set before firstLoad is called');
    _pdfDocument.value ??= await assetCache.pdfDocumentCache.load(
      pdfFile?.path ?? 'inline_pdf_$id.pdf',
      pdfBytes: pdfBytes,
    );
    await _pdfDocument.value!.pages[pdfPage].ensureLoaded();
  }

  @override
  Future<void> loadIn() async => await super.loadIn();

  @override
  Future<bool> loadOut() async => await super.loadOut();

  @override
  Future<void> precache(BuildContext context) async {
    if (_pdfDocument.value != null) return;

    final completer = Completer<void>();

    void onDocumentSet() {
      if (_pdfDocument.value == null) return;
      if (completer.isCompleted) return;
      completer.complete();
      _pdfDocument.removeListener(onDocumentSet);
    }

    _pdfDocument.addListener(onDocumentSet);
    return completer.future;
  }

  @override
  Widget buildImageWidget({
    required BuildContext context,
    required BoxFit? overrideBoxFit,
    required bool isBackground,
    required bool invert,
  }) {
    return ValueListenableBuilder(
      valueListenable: _pdfDocument,
      builder: (context, pdfDocument, child) {
        if (pdfDocument == null) {
          return SizedBox.fromSize(size: srcRect.size);
        }
        final pageView = PdfPageView(
          document: pdfDocument,
          // [PdfPageView.pageNumber] starts at 1 not 0
          pageNumber: pdfPage + 1,
          decoration: const BoxDecoration(),
        );
        return InvertWidget(
          invert: invert,
          child: cropRect == null ? pageView : _buildCropped(pageView),
        );
      },
    );
  }

  /// Maps [region] of a page whose background pdf page has [naturalSize]
  /// to a [cropRect] for that pdf page.
  ///
  /// The background is assumed to be drawn with [fit], centred on a page
  /// of [pageSize].
  ///
  /// Returns the crop in natural units, and the part of [region]
  /// that the crop covers on the page,
  /// or null if [region] doesn't overlap the background.
  static ({Rect crop, Rect onPage})? cropForPageRegion({
    required Rect region,
    required Size pageSize,
    required Size naturalSize,
    required BoxFit fit,
  }) {
    final fittedSizes = applyBoxFit(fit, naturalSize, pageSize);
    final scaleX = fittedSizes.destination.width / fittedSizes.source.width;
    final scaleY = fittedSizes.destination.height / fittedSizes.source.height;
    final pageRect = Offset.zero & pageSize;
    final drawnRect = Alignment.center.inscribe(
      Size(naturalSize.width * scaleX, naturalSize.height * scaleY),
      pageRect,
    );
    final onPage = region.intersect(drawnRect).intersect(pageRect);
    if (onPage.width <= 0 || onPage.height <= 0) return null;

    final shifted = onPage.shift(-drawnRect.topLeft);
    final crop = Rect.fromLTRB(
      shifted.left / scaleX,
      shifted.top / scaleY,
      shifted.right / scaleX,
      shifted.bottom / scaleY,
    );
    return (crop: crop, onPage: onPage);
  }

  /// Renders [pageView] at a scale where [cropRect] fills the available
  /// space, so the cropped region stays as sharp as a full page would be.
  Widget _buildCropped(Widget pageView) {
    final crop = cropRect!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = constraints.maxWidth / crop.width;
        final scaledSize = naturalSize * scale;
        return ClipRect(
          child: OverflowBox(
            alignment: .topLeft,
            minWidth: scaledSize.width,
            maxWidth: scaledSize.width,
            minHeight: scaledSize.height,
            maxHeight: scaledSize.height,
            child: Transform.translate(
              offset: -crop.topLeft * scale,
              child: pageView,
            ),
          ),
        );
      },
    );
  }

  @override
  PdfEditorImage copy() => PdfEditorImage(
    id: id,
    assetCache: assetCache,
    pdfBytes: pdfBytes,
    pdfPage: pdfPage,
    pdfFile: pdfFile,
    cropRect: cropRect,
    pageIndex: pageIndex,
    pageSize: .infinite,
    invertible: invertible,
    backgroundFit: backgroundFit,
    onMoveImage: onMoveImage,
    onDeleteImage: onDeleteImage,
    onMiscChange: onMiscChange,
    onLoad: onLoad,
    newImage: true,
    dstRect: dstRect,
    naturalSize: naturalSize,
    isThumbnail: isThumbnail,
  );

  @override
  void dispose() {
    pdfBytes = null;
    _pdfDocument.dispose();
    super.dispose();
  }
}
