import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../config/app_config.dart';
import '../../../core/display/display_policy.dart';
import '../../../core/errors/paper_exception.dart';
import '../../../core/platform/keep_awake_service.dart';
import '../../../core/platform/pdf_service.dart';
import '../../../shared/widgets/paper_widgets.dart';
import '../../../theme/paper_palette.dart';
import '../../../theme/paper_space.dart';
import '../../../theme/paper_typography.dart';
import '../../annotations/data/annotation_export_service.dart';
import '../../annotations/domain/annotation.dart';
import '../../display/application/display_providers.dart';
import '../../display/application/reader_display_settings.dart';
import '../../library/domain/document.dart';
import '../../settings/application/settings_controller.dart';
import '../../settings/domain/app_settings.dart';
import '../application/reader_controller.dart';
import '../domain/reader_backend.dart';
import '../domain/text_paginator.dart';
import '../epub/epub_book.dart';
import '../epub/epub_reader_backend.dart';

/// Height of the reader's top and bottom bars.
///
/// Named because the page area subtracts them; a magic number repeated in two
/// places would silently drift and clip the first line of every page.
const double kReaderTopBarHeight = 56;
const double kReaderBottomBarHeight = 66;

/// The reader.
///
/// One screen for both formats. Only the page content differs — a rendered
/// bitmap for a PDF, laid-out text for a plain file — while every control,
/// indicator, bookmark, and progress write is shared.
///
/// The chrome is hidden by default and revealed by a tap in the middle of the
/// page, because on an e-ink panel every visible pixel of chrome costs a
/// refresh.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.documentId});

  final String documentId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  Size _pageViewport = Size.zero;
  TextScaler? _reportedTextScaler;
  Timer? _chromeTimer;
  bool _reportedViewport = false;
  late final KeepAwakeService _keepAwake;
  bool _screenHeldOn = false;

  ReaderSession get _session =>
      ref.read(readerProvider(widget.documentId).notifier);

  @override
  void initState() {
    super.initState();
    _keepAwake = ref.read(keepAwakeServiceProvider);
  }

  @override
  void dispose() {
    _chromeTimer?.cancel();
    // Never leave the display pinned on after the reader is gone.
    if (_screenHeldOn) unawaited(_keepAwake.disable());
    super.dispose();
  }

  /// Applies the "keep the screen on" preference to the window, but only when
  /// it actually changed, so a rebuild does not hammer the channel.
  void _syncKeepAwake(bool enabled) {
    if (enabled == _screenHeldOn) return;
    _screenHeldOn = enabled;
    unawaited(enabled ? _keepAwake.enable() : _keepAwake.disable());
  }

  /// Hides the chrome after a period of inactivity, and shows it again the
  /// moment the user touches the page.
  ///
  /// The E-Ink profile deliberately does not auto-hide: leaving the controls
  /// visible avoids a timed full-screen redraw removing them while the reader
  /// is still deciding.
  void _armChromeTimer(bool chromeVisible, [DisplayPolicy? policy]) {
    _chromeTimer?.cancel();
    final DisplayPolicy display = policy ?? ref.read(displayPolicyProvider);
    if (!chromeVisible || !display.autoHideReaderChrome) return;
    _chromeTimer = Timer(PaperConfig.readerChromeAutoHide, () {
      if (!mounted) return;
      _session.toggleChrome();
    });
  }

  void _toggleChrome() {
    _session.toggleChrome();
    _armChromeTimer(true);
  }

  void _showChrome() {
    _session.showChrome();
    _armChromeTimer(true);
  }

  Future<void> _turn({required bool previous}) async {
    _session.onInteraction();
    if (previous) {
      await _session.previousPage();
    } else {
      await _session.nextPage();
    }
    if (!mounted) return;
    // Turning past either end means the user is done; bring the chrome back so
    // the way out is visible.
    final ReaderState? state = ref
        .read(readerProvider(widget.documentId))
        .value;
    if (state == null) return;
    if (previous
        ? state.pageIndex <= 0
        : state.pageIndex >= state.pageCount - 1) {
      _showChrome();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ReaderState> session = ref.watch(
      readerProvider(widget.documentId),
    );

    return Scaffold(
      backgroundColor: paperPalette(context).canvas,
      body: session.when(
        loading: () => const _ReaderLoading(),
        error: (Object error, StackTrace stack) => _ReaderError(error: error),
        data: _buildReader,
      ),
    );
  }

  Widget _buildReader(ReaderState state) {
    final PaperPalette palette = paperPalette(context);
    final DisplayPolicy display = ref.watch(displayPolicyProvider);
    final ReaderSettings baseSettings = ref.watch(settingsProvider).reader;
    final ReaderSettings settings = readerSettingsForDisplay(
      baseSettings,
      display,
    );
    final bool showNumbers = baseSettings.showPageNumbers;

    _syncKeepAwake(baseSettings.keepScreenOn);
    _armChromeTimer(state.chromeVisible, display);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: palette.isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarColor: palette.canvas,
        systemNavigationBarIconBrightness: palette.isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: _PageSurface(
              state: state,
              settings: settings,
              onViewport: _onViewport,
              onTapZone: _onTapZone,
              onSwipe: _onSwipe,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _ReaderTopBar(
              state: state,
              visible: state.chromeVisible,
              showPageNumbers: showNumbers,
              onBack: () => Navigator.of(context).maybePop(),
              onToc: _showToc,
              onSearch: _showSearch,
              onAnnotations: _showAnnotations,
              onBookmarks: () => _showBookmarks(state),
              onExportMarkdown: () =>
                  _exportAnnotations(AnnotationExportFormat.markdown),
              onExportJson: () =>
                  _exportAnnotations(AnnotationExportFormat.json),
              onSettings: _showReadingSettings,
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _ReaderBottomBar(
              state: state,
              visible: state.chromeVisible,
              onPrevious: () => _turn(previous: true),
              onNext: () => _turn(previous: false),
              onGoToPage: () => _promptForPage(state),
              onToggleBookmark: () => _toggleBookmark(state),
            ),
          ),
        ],
      ),
    );
  }

  void _onViewport(Size size) {
    if (size.isEmpty) return;
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    if (size == _pageViewport && scaler == _reportedTextScaler) return;
    _pageViewport = size;
    _reportedTextScaler = scaler;
    _reportedViewport = true;
    // Text pagination is measured against the page area, which is only known
    // after the first layout, so the session is told about it a frame later.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _session.setViewport(size, textScaler: scaler);
    });
  }

  void _onTapZone(Offset position, Size size) {
    _session.onInteraction();
    final double fraction = size.width <= 0 ? 0.5 : position.dx / size.width;
    final double zone = ref.read(displayPolicyProvider).pageTurnZoneFraction;
    if (fraction < zone) {
      _turn(previous: true);
    } else if (fraction > 1 - zone) {
      _turn(previous: false);
    } else {
      _toggleChrome();
    }
  }

  void _onSwipe(DragEndDetails details) {
    if (ref.read(displayPolicyProvider).forceTapPageTurns) return;
    final double velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 180) return;
    _turn(previous: velocity > 0);
  }

  Future<void> _promptForPage(ReaderState state) async {
    final int total = state.pageCount;
    final String? answer = await showPaperTextPrompt(
      context,
      title: 'Go to page',
      label: total > 0 ? '1 to $total' : 'Page number',
      initialValue: '${state.pageIndex + 1}',
      confirmLabel: 'Go',
      keyboardType: TextInputType.number,
      maxLength: 6,
    );
    if (answer == null || !mounted) return;
    final int? page = int.tryParse(answer);
    if (page == null || page < 1) return;
    await _session.goToPage(page - 1);
  }

  Future<void> _toggleBookmark(ReaderState state) async {
    final bool wasMarked = state.isBookmarked;
    final String label = state.backend.positionLabel;
    await _session.toggleBookmark();
    if (!mounted) return;
    PaperToast.show(
      context,
      wasMarked ? 'Bookmark removed' : 'Bookmarked $label',
      icon: wasMarked ? Icons.bookmark_border : Icons.bookmark,
    );
  }

  Future<void> _showBookmarks(ReaderState state) async {
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: paperModalAnimationStyle(context),
      backgroundColor: paperPalette(context).canvas,
      barrierColor: paperPalette(context).ink.withValues(alpha: 0.32),
      shape: const RoundedRectangleBorder(),
      builder: (BuildContext sheetContext) {
        return _BookmarksSheet(state: state);
      },
    );
  }

  Future<void> _showToc() async {
    final ReaderSession session = _session;
    if (session.toc.isEmpty) {
      PaperToast.show(context, 'This EPUB has no table of contents.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: paperModalAnimationStyle(context),
      isScrollControlled: true,
      backgroundColor: paperPalette(context).canvas,
      barrierColor: paperPalette(context).ink.withValues(alpha: 0.32),
      shape: const RoundedRectangleBorder(),
      builder: (BuildContext sheetContext) =>
          _TocSheet(entries: session.toc, session: session),
    );
  }

  Future<void> _showSearch() async {
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: paperModalAnimationStyle(context),
      isScrollControlled: true,
      backgroundColor: paperPalette(context).canvas,
      barrierColor: paperPalette(context).ink.withValues(alpha: 0.32),
      shape: const RoundedRectangleBorder(),
      builder: (BuildContext sheetContext) => _SearchSheet(session: _session),
    );
  }

  Future<void> _showAnnotations() async {
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: paperModalAnimationStyle(context),
      isScrollControlled: true,
      backgroundColor: paperPalette(context).canvas,
      barrierColor: paperPalette(context).ink.withValues(alpha: 0.32),
      shape: const RoundedRectangleBorder(),
      builder: (BuildContext sheetContext) => _AnnotationsSheet(
        documentId: widget.documentId,
        onExportMarkdown: () =>
            _exportAnnotations(AnnotationExportFormat.markdown),
        onExportJson: () => _exportAnnotations(AnnotationExportFormat.json),
      ),
    );
  }

  Future<void> _exportAnnotations(AnnotationExportFormat format) async {
    try {
      final String? saved = await ref
          .read(annotationExportServiceProvider)
          .export(widget.documentId, format);
      if (!mounted || saved == null) return;
      PaperToast.show(
        context,
        'Annotations exported as ${format.label}',
        icon: Icons.ios_share_outlined,
      );
    } on PaperException catch (error) {
      if (!mounted) return;
      PaperToast.show(context, error.message, icon: Icons.error_outline);
    }
  }

  /// Reading settings are edited in place: every change re-paginates the text
  /// immediately, so the user sees the effect of a font size without leaving
  /// the document.
  Future<void> _showReadingSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: paperModalAnimationStyle(context),
      isScrollControlled: true,
      backgroundColor: paperPalette(context).canvas,
      barrierColor: paperPalette(context).ink.withValues(alpha: 0.32),
      shape: const RoundedRectangleBorder(),
      builder: (BuildContext sheetContext) {
        return _ReadingSettingsSheet(session: _session);
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The system font scale can change while the reader is open (or after the
    // app resumes with a different accessibility setting). Measured text pages
    // are only valid for one scale, so report the viewport again and let the
    // session re-paginate at the new scale.
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    if (_reportedViewport && scaler != _reportedTextScaler) {
      _reportedTextScaler = scaler;
      final Size size = _pageViewport;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !size.isEmpty) {
          _session.setViewport(size, textScaler: scaler);
        }
      });
    }
  }
}

class _ReaderLoading extends StatelessWidget {
  const _ReaderLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: PaperLoading(label: 'Opening'));
  }
}

class _ReaderError extends StatelessWidget {
  const _ReaderError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final String message = error is PaperException
        ? (error as PaperException).message
        : 'This document could not be opened.';

    return SafeArea(
      child: Column(
        children: <Widget>[
          PaperTopBar(title: 'Reader'),
          Expanded(
            child: PaperErrorView(
              title: 'Cannot open this document',
              message: message,
              onRetry: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }
}

/// The page area: what is drawn, and the gesture surface over it.
class _PageSurface extends ConsumerStatefulWidget {
  const _PageSurface({
    required this.state,
    required this.settings,
    required this.onViewport,
    required this.onTapZone,
    required this.onSwipe,
  });

  final ReaderState state;
  final ReaderSettings settings;
  final ValueChanged<Size> onViewport;
  final void Function(Offset position, Size size) onTapZone;
  final ValueChanged<DragEndDetails> onSwipe;

  @override
  ConsumerState<_PageSurface> createState() => _PageSurfaceState();
}

class _PageSurfaceState extends ConsumerState<_PageSurface> {
  Size _lastReported = Size.zero;

  @override
  Widget build(BuildContext context) {
    final ReaderState state = widget.state;
    final DisplayPolicy display = DisplayPolicyScope.of(context);
    final PageTurnMode mode = display.forceTapPageTurns
        ? PageTurnMode.tap
        : widget.settings.turnMode;
    final bool scrolling =
        !display.forcePagedReader &&
        state.backend is EpubReaderBackend &&
        widget.settings.flow == ReaderFlow.scroll;
    final EdgeInsets chromeInset = EdgeInsets.only(
      top: kReaderTopBarHeight + MediaQuery.paddingOf(context).top,
      bottom: kReaderBottomBarHeight + MediaQuery.paddingOf(context).bottom,
    );
    final ReaderSession session = ref.read(
      readerProvider(state.document.id).notifier,
    );

    final Widget content = switch (state.backend) {
      final PdfReaderBackend backend => _PdfPage(
        backend: backend,
        inset: chromeInset,
      ),
      final TextReaderBackend backend => _TextPage(
        paginator: backend.paginator,
        pageIndex: state.pageIndex,
        settings: widget.settings,
        serifReading: ref.watch(settingsProvider).appearance.serifReading,
        inset: chromeInset,
      ),
      final EpubReaderBackend backend when scrolling => _EpubScrollPage(
        state: state,
        backend: backend,
        settings: widget.settings,
        serifReading: ref.watch(settingsProvider).appearance.serifReading,
        session: session,
      ),
      final EpubReaderBackend backend => _EpubPage(
        state: state,
        backend: backend,
        settings: widget.settings,
        serifReading: ref.watch(settingsProvider).appearance.serifReading,
        session: session,
      ),
      final ReaderBackend _ => const Center(child: PaperLoading()),
    };

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        // Text is paginated against the area the page actually occupies: the
        // full width minus margins, and the height left after the bars. Report
        // geometry only when it changes so the session is not re-paginated on
        // every frame.
        final Size contentSize = Size(
          size.width,
          (size.height - chromeInset.vertical).clamp(0.0, double.infinity),
        );
        if (contentSize != _lastReported && !contentSize.isEmpty) {
          _lastReported = contentSize;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onViewport(contentSize);
          });
        }

        Widget page = Padding(padding: chromeInset, child: content);
        if (mode != PageTurnMode.swipe) {
          page = _TapZones(onTap: widget.onTapZone, child: page);
        }
        if (!scrolling && mode != PageTurnMode.tap) {
          page = _SwipeTurns(onHorizontalDragEnd: widget.onSwipe, child: page);
        }
        return page;
      },
    );
  }
}

class _TapZones extends StatelessWidget {
  const _TapZones({required this.child, required this.onTap});

  final Widget child;
  final void Function(Offset position, Size size) onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (TapUpDetails details) => onTap(details.localPosition, size),
          child: child,
        );
      },
    );
  }
}

class _SwipeTurns extends StatelessWidget {
  const _SwipeTurns({required this.child, required this.onHorizontalDragEnd});

  final Widget child;
  final ValueChanged<DragEndDetails> onHorizontalDragEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: onHorizontalDragEnd,
      child: child,
    );
  }
}

/// A rendered PDF page.
///
/// The previous page stays on screen while the next one is rasterised. A
/// blank flash on every turn is a worse trade than a frame of latency, and it
/// is the difference between reading a book and flipping a slideshow.
class _PdfPage extends ConsumerStatefulWidget {
  const _PdfPage({required this.backend, required this.inset});

  final PdfReaderBackend backend;
  final EdgeInsets inset;

  @override
  ConsumerState<_PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends ConsumerState<_PdfPage> {
  PdfPageImage? _shown;
  int _shownIndex = -1;
  double? _targetWidthPx;
  String? _error;

  @override
  void initState() {
    super.initState();
    _shownIndex = widget.backend.pageIndex;
  }

  @override
  void didUpdateWidget(_PdfPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.backend.pageIndex != _shownIndex && _targetWidthPx != null) {
      _request(widget.backend.pageIndex, _targetWidthPx!);
    }
  }

  Future<void> _request(int index, double widthPx) async {
    if (widthPx <= 0) return;
    try {
      final PdfPageImage image = await ref
          .read(pdfServiceProvider)
          .renderPage(widget.backend.handleId, index, widthPx: widthPx.round());
      if (!mounted) return;
      setState(() {
        _shown = image;
        _shownIndex = index;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is PaperException
            ? error.message
            : 'This page could not be drawn.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        if (width <= 0) return const SizedBox.shrink();

        final double target = (width * MediaQuery.devicePixelRatioOf(context))
            .clamp(480.0, 2048.0);
        final bool widthChanged =
            _targetWidthPx == null || (_targetWidthPx! - target).abs() > 32;
        if (widthChanged) {
          _targetWidthPx = target;
          _error = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _request(widget.backend.pageIndex, target);
          });
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: PaperSpace.sm),
          child: Center(
            child: AspectRatio(
              aspectRatio: widget.backend.pageAspectRatio ?? 0.7071,
              child: _PdfBitmap(image: _shown, palette: palette, error: _error),
            ),
          ),
        );
      },
    );
  }
}

class _PdfBitmap extends StatelessWidget {
  const _PdfBitmap({required this.image, required this.palette, this.error});

  final PdfPageImage? image;
  final PaperPalette palette;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final String? failure = error;
    if (failure != null) {
      return ColoredBox(
        color: palette.rule,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(PaperSpace.lg),
            child: Text(
              failure,
              textAlign: TextAlign.center,
              style: PaperTypography.of(context).caption,
            ),
          ),
        ),
      );
    }
    final PdfPageImage? rendered = image;
    if (rendered == null) {
      return ColoredBox(
        color: palette.rule,
        child: const Center(child: PaperLoading()),
      );
    }
    return Image.memory(
      rendered.png,
      gaplessPlayback: true,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
        return ColoredBox(
          color: palette.rule,
          child: Center(
            child: Text(
              'This page could not be drawn.',
              style: PaperTypography.of(context).caption,
            ),
          ),
        );
      },
    );
  }
}

/// A page of plain text.
class _TextPage extends StatelessWidget {
  const _TextPage({
    required this.paginator,
    required this.pageIndex,
    required this.settings,
    required this.serifReading,
    required this.inset,
  });

  final TextPaginator paginator;
  final int pageIndex;
  final ReaderSettings settings;
  final bool serifReading;
  final EdgeInsets inset;

  @override
  Widget build(BuildContext context) {
    final PaperTypography type = PaperTypography.of(context);

    if (paginator.isEmptyDocument) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(PaperSpace.xl),
          child: Text(
            'This file is empty.',
            style: type.bodyQuiet,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final TextPage page = paginator.pageAt(pageIndex);
    final TextStyle style = ReadingTextStyle.forReader(
      fontSizeScale: settings.fontSize,
      lineHeight: settings.lineHeight,
      serifFamily: serifReading ? kPaperSerifFamily : null,
    ).toTextStyle().copyWith(color: type.palette.ink);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: settings.margin),
      child: Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          child: Text(page.text, style: style, textAlign: TextAlign.justify),
        ),
      ),
    );
  }
}

/// A paginated EPUB page with selectable text and inline annotations.
class _EpubPage extends StatefulWidget {
  const _EpubPage({
    required this.state,
    required this.backend,
    required this.settings,
    required this.serifReading,
    required this.session,
  });

  final ReaderState state;
  final EpubReaderBackend backend;
  final ReaderSettings settings;
  final bool serifReading;
  final ReaderSession session;

  @override
  State<_EpubPage> createState() => _EpubPageState();
}

class _EpubPageState extends State<_EpubPage> {
  @override
  Widget build(BuildContext context) {
    final PaperTypography type = PaperTypography.of(context);
    final PaperPalette palette = type.palette;
    final TextPage page = widget.backend.currentPage;
    final TextStyle style = _readingStyle(
      widget.settings,
      widget.serifReading,
      palette,
    );
    final List<EpubAnnotationSpan> spans = widget.backend.spansForPage(
      widget.state.pageIndex,
      widget.state.annotations,
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.settings.margin),
      child: Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          child: SelectableText.rich(
            TextSpan(
              style: style,
              children: _annotationSpans(
                text: page.text,
                baseOffset: page.start,
                spans: spans,
                baseStyle: style,
                palette: palette,
              ),
            ),
            textAlign: TextAlign.justify,
            contextMenuBuilder:
                (BuildContext context, EditableTextState state) {
                  return _selectionToolbar(
                    context: context,
                    state: state,
                    session: widget.session,
                    baseOffset: page.start,
                  );
                },
          ),
        ),
      ),
    );
  }
}

/// A continuous EPUB, with the same selectable text and annotation rendering as
/// the paged surface. Scroll position is stored as text fraction plus a stable
/// chapter locator, so reopening resumes near the same paragraph.
class _EpubScrollPage extends StatefulWidget {
  const _EpubScrollPage({
    required this.state,
    required this.backend,
    required this.settings,
    required this.serifReading,
    required this.session,
  });

  final ReaderState state;
  final EpubReaderBackend backend;
  final ReaderSettings settings;
  final bool serifReading;
  final ReaderSession session;

  @override
  State<_EpubScrollPage> createState() => _EpubScrollPageState();
}

class _EpubScrollPageState extends State<_EpubScrollPage> {
  final ScrollController _controller = ScrollController();
  bool _initialised = false;
  bool _programmatic = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreInitial());
  }

  @override
  void didUpdateWidget(_EpubScrollPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final double? target = widget.state.scrollRequestFraction;
    if (target != null &&
        widget.state.scrollRequestId != oldWidget.state.scrollRequestId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToFraction(target);
      });
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _restoreInitial() {
    if (_initialised || !mounted) return;
    _initialised = true;
    _jumpToFraction(widget.state.initialScrollFraction);
  }

  void _jumpToFraction(double fraction) {
    if (!_controller.hasClients) return;
    final double max = _controller.position.maxScrollExtent;
    if (max <= 0) return;
    _programmatic = true;
    _controller.jumpTo((max * fraction.clamp(0.0, 1.0)).clamp(0.0, max));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _programmatic = false;
    });
  }

  void _onScroll() {
    if (_programmatic ||
        !_controller.hasClients ||
        _controller.position.maxScrollExtent <= 0) {
      return;
    }
    final double fraction =
        _controller.offset / _controller.position.maxScrollExtent;
    widget.session.setScrollFraction(fraction);
  }

  @override
  Widget build(BuildContext context) {
    final PaperTypography type = PaperTypography.of(context);
    final PaperPalette palette = type.palette;
    final TextStyle style = _readingStyle(
      widget.settings,
      widget.serifReading,
      palette,
    );
    final List<EpubAnnotationSpan> spans = widget.backend.annotationSpans(
      widget.state.annotations,
    );

    return Scrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        controller: _controller,
        padding: EdgeInsets.fromLTRB(
          widget.settings.margin,
          PaperSpace.md,
          widget.settings.margin,
          PaperSpace.xl,
        ),
        child: SelectableText.rich(
          TextSpan(
            style: style,
            children: _annotationSpans(
              text: widget.backend.book.text,
              baseOffset: 0,
              spans: spans,
              baseStyle: style,
              palette: palette,
            ),
          ),
          textAlign: TextAlign.justify,
          contextMenuBuilder: (BuildContext context, EditableTextState state) {
            return _selectionToolbar(
              context: context,
              state: state,
              session: widget.session,
              baseOffset: 0,
            );
          },
        ),
      ),
    );
  }
}

TextStyle _readingStyle(
  ReaderSettings settings,
  bool serifReading,
  PaperPalette palette,
) {
  return ReadingTextStyle.forReader(
    fontSizeScale: settings.fontSize,
    lineHeight: settings.lineHeight,
    serifFamily: serifReading ? kPaperSerifFamily : null,
  ).toTextStyle().copyWith(color: palette.ink);
}

List<TextSpan> _annotationSpans({
  required String text,
  required int baseOffset,
  required List<EpubAnnotationSpan> spans,
  required TextStyle baseStyle,
  required PaperPalette palette,
}) {
  final List<EpubAnnotationSpan> relevant = spans
      .where(
        (EpubAnnotationSpan span) =>
            span.end > baseOffset && span.start < baseOffset + text.length,
      )
      .toList(growable: false);
  if (relevant.isEmpty) {
    return <TextSpan>[TextSpan(text: text, style: baseStyle)];
  }

  final Set<int> cuts = <int>{0, text.length};
  for (final EpubAnnotationSpan span in relevant) {
    cuts
      ..add((span.start - baseOffset).clamp(0, text.length))
      ..add((span.end - baseOffset).clamp(0, text.length));
  }
  final List<int> ordered = cuts.toList()..sort();
  final List<TextSpan> result = <TextSpan>[];
  for (int i = 0; i + 1 < ordered.length; i++) {
    final int start = ordered[i];
    final int end = ordered[i + 1];
    if (end <= start) continue;
    final int globalStart = baseOffset + start;
    final int globalEnd = baseOffset + end;
    final List<EpubAnnotationSpan> active = relevant
        .where(
          (EpubAnnotationSpan span) =>
              span.start <= globalStart && span.end >= globalEnd,
        )
        .toList(growable: false);
    TextStyle style = baseStyle;
    if (active.isNotEmpty) {
      final bool highlight = active.any(
        (EpubAnnotationSpan span) => span.kind == AnnotationKind.highlight.id,
      );
      final bool note = active.any(
        (EpubAnnotationSpan span) =>
            span.kind == AnnotationKind.note.id || span.hasNote,
      );
      final bool underline = active.any(
        (EpubAnnotationSpan span) => span.kind == AnnotationKind.underline.id,
      );
      if (highlight) style = style.copyWith(backgroundColor: palette.rule);
      if (note) {
        style = style.copyWith(
          backgroundColor: palette.inkFaint.withValues(alpha: 0.18),
        );
      }
      if (underline || note) {
        style = style.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: palette.ink,
          decorationStyle: note
              ? TextDecorationStyle.dotted
              : TextDecorationStyle.solid,
        );
      }
    }
    result.add(TextSpan(text: text.substring(start, end), style: style));
  }
  return result;
}

Widget _selectionToolbar({
  required BuildContext context,
  required EditableTextState state,
  required ReaderSession session,
  required int baseOffset,
}) {
  final TextSelection selection = state.textEditingValue.selection;
  final List<ContextMenuButtonItem> items = List<ContextMenuButtonItem>.of(
    state.contextMenuButtonItems,
  );
  if (selection.isValid && !selection.isCollapsed) {
    void add(AnnotationKind kind) {
      state.hideToolbar();
      unawaited(
        _addAnnotation(
          context: context,
          session: session,
          kind: kind,
          start: baseOffset + selection.start,
          end: baseOffset + selection.end,
        ),
      );
    }

    items.addAll(<ContextMenuButtonItem>[
      ContextMenuButtonItem(
        label: 'Highlight',
        onPressed: () => add(AnnotationKind.highlight),
      ),
      ContextMenuButtonItem(
        label: 'Underline',
        onPressed: () => add(AnnotationKind.underline),
      ),
      ContextMenuButtonItem(
        label: 'Add note',
        onPressed: () => add(AnnotationKind.note),
      ),
    ]);
  }
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: state.contextMenuAnchors,
    buttonItems: items,
  );
}

Future<void> _addAnnotation({
  required BuildContext context,
  required ReaderSession session,
  required AnnotationKind kind,
  required int start,
  required int end,
}) async {
  String? note;
  if (kind == AnnotationKind.note) {
    note = await showPaperTextPrompt(
      context,
      title: 'Attach a note',
      label: 'Note',
      confirmLabel: 'Save note',
      maxLength: 2000,
    );
    if (note == null || note.trim().isEmpty) return;
  }
  try {
    await session.addAnnotation(kind: kind, start: start, end: end, note: note);
    if (!context.mounted) return;
    PaperToast.show(
      context,
      kind == AnnotationKind.note ? 'Note saved' : '${kind.label} saved',
      icon: kind == AnnotationKind.note
          ? Icons.sticky_note_2_outlined
          : Icons.format_quote_outlined,
    );
  } on PaperException catch (error) {
    if (!context.mounted) return;
    PaperToast.show(context, error.message, icon: Icons.error_outline);
  }
}

class _ReaderTopBar extends StatelessWidget {
  const _ReaderTopBar({
    required this.state,
    required this.visible,
    required this.showPageNumbers,
    required this.onBack,
    required this.onToc,
    required this.onSearch,
    required this.onAnnotations,
    required this.onBookmarks,
    required this.onExportMarkdown,
    required this.onExportJson,
    required this.onSettings,
  });

  final ReaderState state;
  final bool visible;
  final bool showPageNumbers;
  final VoidCallback onBack;
  final VoidCallback onToc;
  final VoidCallback onSearch;
  final VoidCallback onAnnotations;
  final VoidCallback onBookmarks;
  final VoidCallback onExportMarkdown;
  final VoidCallback onExportJson;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);
    final bool isEpub = state.backend is EpubReaderBackend;

    return _AnimatedBar(
      visible: visible,
      fromTop: true,
      child: Container(
        color: palette.canvas,
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: SizedBox(
          height: kReaderTopBarHeight,
          child: Row(
            children: <Widget>[
              const SizedBox(width: PaperSpace.xs),
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      state.document.title,
                      style: type.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showPageNumbers)
                      Text(
                        state.positionLabel,
                        style: type.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (isEpub)
                IconButton(
                  onPressed: onSearch,
                  icon: const Icon(Icons.search),
                  tooltip: 'Search in book',
                ),
              PopupMenuButton<_ReaderMenuAction>(
                tooltip: 'Reader menu',
                icon: const Icon(Icons.more_vert),
                onSelected: (_ReaderMenuAction action) {
                  switch (action) {
                    case _ReaderMenuAction.toc:
                      onToc();
                      break;
                    case _ReaderMenuAction.bookmarks:
                      onBookmarks();
                      break;
                    case _ReaderMenuAction.annotations:
                      onAnnotations();
                      break;
                    case _ReaderMenuAction.exportMarkdown:
                      onExportMarkdown();
                      break;
                    case _ReaderMenuAction.exportJson:
                      onExportJson();
                      break;
                    case _ReaderMenuAction.settings:
                      onSettings();
                      break;
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<_ReaderMenuAction>>[
                      if (isEpub)
                        const PopupMenuItem<_ReaderMenuAction>(
                          value: _ReaderMenuAction.toc,
                          child: _MenuRow(
                            icon: Icons.list_alt_outlined,
                            label: 'Contents',
                          ),
                        ),
                      PopupMenuItem<_ReaderMenuAction>(
                        value: _ReaderMenuAction.bookmarks,
                        child: _MenuRow(
                          icon: Icons.bookmarks_outlined,
                          label: 'Bookmarks (${state.bookmarks.length})',
                        ),
                      ),
                      if (isEpub)
                        PopupMenuItem<_ReaderMenuAction>(
                          value: _ReaderMenuAction.annotations,
                          child: _MenuRow(
                            icon: Icons.format_quote_outlined,
                            label: 'Annotations (${state.annotations.length})',
                          ),
                        ),
                      const PopupMenuItem<_ReaderMenuAction>(
                        value: _ReaderMenuAction.exportMarkdown,
                        child: _MenuRow(
                          icon: Icons.description_outlined,
                          label: 'Export annotations (Markdown)',
                        ),
                      ),
                      const PopupMenuItem<_ReaderMenuAction>(
                        value: _ReaderMenuAction.exportJson,
                        child: _MenuRow(
                          icon: Icons.data_object,
                          label: 'Export annotations (JSON)',
                        ),
                      ),
                      const PopupMenuItem<_ReaderMenuAction>(
                        value: _ReaderMenuAction.settings,
                        child: _MenuRow(
                          icon: Icons.text_fields,
                          label: 'Reading settings',
                        ),
                      ),
                    ],
              ),
              const SizedBox(width: PaperSpace.xs),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ReaderMenuAction {
  toc,
  bookmarks,
  annotations,
  exportMarkdown,
  exportJson,
  settings,
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 18),
        const SizedBox(width: PaperSpace.sm),
        Text(label),
      ],
    );
  }
}

class _ReaderBottomBar extends StatelessWidget {
  const _ReaderBottomBar({
    required this.state,
    required this.visible,
    required this.onPrevious,
    required this.onNext,
    required this.onGoToPage,
    required this.onToggleBookmark,
  });

  final ReaderState state;
  final bool visible;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onGoToPage;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);
    final bool first = state.pageIndex <= 0 && state.scrollPosition == null;
    final bool last =
        state.pageIndex >= state.pageCount - 1 && state.scrollPosition == null;
    final bool scrolling = state.scrollPosition != null;

    return _AnimatedBar(
      visible: visible,
      fromTop: false,
      child: Container(
        color: palette.canvas,
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: SizedBox(
          height: kReaderBottomBarHeight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PaperSpace.lg),
                child: PaperProgressBar(value: state.progress),
              ),
              const SizedBox(height: PaperSpace.xs + PaperSpace.xs),
              Row(
                children: <Widget>[
                  const SizedBox(width: PaperSpace.sm),
                  IconButton(
                    onPressed: first ? null : onPrevious,
                    icon: const Icon(Icons.chevron_left),
                    tooltip: scrolling ? 'Scroll back' : 'Previous page',
                  ),
                  Expanded(
                    child: Center(
                      child: InkWell(
                        onTap: onGoToPage,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: PaperSpace.sm,
                            horizontal: PaperSpace.md,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  state.positionLabel,
                                  style: type.meta,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!state.backend.isPageCountExact &&
                                  !scrolling) ...<Widget>[
                                const SizedBox(width: PaperSpace.xs),
                                Tooltip(
                                  message:
                                      'An estimate, until you reach the end '
                                      'of the document.',
                                  child: Icon(
                                    Icons.info_outline,
                                    size: 14,
                                    color: palette.inkFaint,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: last ? null : onNext,
                    icon: const Icon(Icons.chevron_right),
                    tooltip: scrolling ? 'Scroll forward' : 'Next page',
                  ),
                  IconButton(
                    onPressed: onToggleBookmark,
                    icon: Icon(
                      state.isBookmarked
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                    ),
                    tooltip: state.isBookmarked
                        ? 'Remove bookmark'
                        : 'Add bookmark',
                  ),
                  const SizedBox(width: PaperSpace.xs),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slides the reader's chrome away instead of snapping it.
///
/// A 140 ms slide is short enough to feel instant and long enough to explain
/// where the controls went; anything longer would delay the next page turn.
class _AnimatedBar extends StatelessWidget {
  const _AnimatedBar({
    required this.visible,
    required this.fromTop,
    required this.child,
  });

  final bool visible;
  final bool fromTop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final DisplayPolicy display = DisplayPolicyScope.of(context);
    return AnimatedSlide(
      offset: visible ? Offset.zero : Offset(0, fromTop ? -1 : 1),
      duration: display.chromeAnimationDuration,
      curve: Curves.easeOutCubic,
      child: child,
    );
  }
}

/// The bookmark list for the open document.
class _BookmarksSheet extends ConsumerWidget {
  const _BookmarksSheet({required this.state});

  final ReaderState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PaperPalette palette = paperPalette(context);
    final ReaderSession session = ref.read(
      readerProvider(state.document.id).notifier,
    );

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PaperSpace.gutter,
              PaperSpace.lg,
              PaperSpace.gutter,
              PaperSpace.sm,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Bookmarks',
                    style: PaperTypography.of(context).heading,
                  ),
                ),
                PaperButton(
                  label: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const PaperRule(strong: true),
          if (state.bookmarks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: PaperSpace.xxl),
              child: Text(
                'No bookmarks yet. Tap the ribbon in the bottom bar while '
                'reading to mark a page.',
                style: PaperTypography.of(context).bodyQuiet,
                textAlign: TextAlign.center,
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: state.bookmarks.length,
                itemBuilder: (BuildContext context, int index) {
                  final Bookmark bookmark = state.bookmarks[index];
                  return PaperListTile(
                    title: bookmark.describe(state.pageCount),
                    subtitle: bookmark.excerpt,
                    leading: Icon(
                      Icons.bookmark_border,
                      size: 20,
                      color: palette.inkMuted,
                    ),
                    trailing: IconButton(
                      onPressed: () => session.removeBookmark(bookmark.id),
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Remove bookmark',
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      session.goToBookmark(bookmark);
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: PaperSpace.sm),
        ],
      ),
    );
  }
}

/// The nested table of contents for an EPUB.
class _TocSheet extends StatelessWidget {
  const _TocSheet({required this.entries, required this.session});

  final List<EpubTocEntry> entries;
  final ReaderSession session;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    final List<EpubTocEntry> flat = <EpubTocEntry>[
      for (final EpubTocEntry entry in entries) ...entry.flattened,
    ];

    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: <Widget>[
            _SheetHeader(
              title: 'Contents',
              onClose: () => Navigator.of(context).pop(),
            ),
            const PaperRule(strong: true),
            Expanded(
              child: ListView.builder(
                itemCount: flat.length,
                itemBuilder: (BuildContext context, int index) {
                  final EpubTocEntry entry = flat[index];
                  return PaperListTile(
                    title: entry.title,
                    dense: true,
                    leading: SizedBox(
                      width: 18 + entry.depth * 16,
                      child: Icon(
                        Icons.article_outlined,
                        size: 17,
                        color: palette.inkMuted,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      session.goToTocEntry(entry);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// In-book search. Results are chapter excerpts with a stable text offset, so
/// tapping one navigates without depending on the current pagination.
class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.session});

  final ReaderSession session;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<EpubSearchResult> _results = const <EpubSearchResult>[];
  String _query = '';
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    setState(() {
      _query = query;
      if (query.trim().length < 2) {
        _results = const <EpubSearchResult>[];
        _searching = false;
      } else {
        _searching = true;
      }
    });
    if (query.trim().length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      final List<EpubSearchResult> results = widget.session.search(query);
      setState(() {
        _results = results;
        _searching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final PaperTypography type = PaperTypography.of(context);
    final PaperPalette palette = paperPalette(context);

    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          children: <Widget>[
            _SheetHeader(
              title: 'Search in book',
              onClose: () => Navigator.of(context).pop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PaperSpace.gutter,
                PaperSpace.sm,
                PaperSpace.gutter,
                PaperSpace.sm,
              ),
              child: PaperSearchField(
                controller: _controller,
                autofocus: true,
                hintText: 'At least two letters',
                onChanged: _onChanged,
              ),
            ),
            const PaperRule(strong: true),
            Expanded(
              child: _searching
                  ? const PaperLoading(label: 'Searching')
                  : _query.trim().length < 2
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(PaperSpace.xl),
                        child: Text(
                          'Search this book for a word or phrase. Results show '
                          'the chapter and a little context.',
                          style: type.bodyQuiet,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : _results.isEmpty
                  ? Center(
                      child: Text(
                        'No matches for "${_query.trim()}".',
                        style: type.bodyQuiet,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (BuildContext context, int index) {
                        final EpubSearchResult result = _results[index];
                        return PaperListTile(
                          title: result.chapterTitle,
                          subtitle: result.excerpt,
                          leading: Icon(
                            Icons.search,
                            size: 18,
                            color: palette.inkMuted,
                          ),
                          onTap: () {
                            Navigator.of(context).pop();
                            widget.session.goToOffset(result.globalOffset);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The annotation library for the open document. Unresolved anchors remain
/// visible with their excerpt and note instead of disappearing.
class _AnnotationsSheet extends ConsumerWidget {
  const _AnnotationsSheet({
    required this.documentId,
    required this.onExportMarkdown,
    required this.onExportJson,
  });

  final String documentId;
  final VoidCallback onExportMarkdown;
  final VoidCallback onExportJson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ReaderState> asyncState = ref.watch(
      readerProvider(documentId),
    );
    final ReaderState? current = asyncState.value;
    if (current == null) {
      return const SafeArea(
        top: false,
        child: SizedBox(height: 280, child: PaperLoading(label: 'Annotations')),
      );
    }
    final ReaderSession session = ref.read(readerProvider(documentId).notifier);
    final PaperPalette palette = paperPalette(context);

    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.76,
        child: Column(
          children: <Widget>[
            _SheetHeader(
              title: 'Annotations',
              onClose: () => Navigator.of(context).pop(),
            ),
            const PaperRule(strong: true),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PaperSpace.gutter,
                PaperSpace.sm,
                PaperSpace.gutter,
                PaperSpace.xs,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Export this book’s notes',
                      style: PaperTypography.of(context).caption
                          .copyWith(color: palette.inkFaint),
                    ),
                  ),
                  PaperButton(
                    label: 'Markdown',
                    onPressed: () {
                      Navigator.of(context).pop();
                      onExportMarkdown();
                    },
                  ),
                  const SizedBox(width: PaperSpace.sm),
                  PaperButton(
                    label: 'JSON',
                    onPressed: () {
                      Navigator.of(context).pop();
                      onExportJson();
                    },
                  ),
                ],
              ),
            ),
            const PaperRule(inset: PaperSpace.gutter),
            if (current.annotations.isEmpty)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(PaperSpace.xl),
                    child: Text(
                      'Select a passage and choose Highlight, Underline or '
                      'Add note. Annotations stay anchored to the text when '
                      'the type size or screen changes.',
                      style: PaperTypography.of(context).bodyQuiet,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: current.annotations.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Annotation annotation = current.annotations[index];
                    return _AnnotationTile(
                      annotation: annotation,
                      palette: palette,
                      onOpen: annotation.orphaned
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              session.goToAnnotation(annotation);
                            },
                      onEdit: () => _editNote(context, session, annotation),
                      onDelete: () => _delete(context, session, annotation),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editNote(
    BuildContext context,
    ReaderSession session,
    Annotation annotation,
  ) async {
    final String? note = await showPaperTextPrompt(
      context,
      title: 'Note',
      label: annotation.excerpt,
      initialValue: annotation.note ?? '',
      confirmLabel: 'Save',
      maxLength: 2000,
    );
    if (note == null) return;
    await session.updateAnnotationNote(annotation.id, note);
  }

  Future<void> _delete(
    BuildContext context,
    ReaderSession session,
    Annotation annotation,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      animationStyle: paperModalAnimationStyle(context),
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: paperPalette(context).canvas,
          title: const Text('Delete annotation?'),
          content: const Text('The highlight and its note will be removed.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) await session.deleteAnnotation(annotation.id);
  }
}

class _AnnotationTile extends StatelessWidget {
  const _AnnotationTile({
    required this.annotation,
    required this.palette,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final Annotation annotation;
  final PaperPalette palette;
  final VoidCallback? onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final String chapter = annotation.chapterTitle?.trim() ?? '';
    final String title = annotation.orphaned
        ? 'Unresolved passage'
        : chapter.isEmpty
        ? annotation.kind.label
        : chapter;
    final List<String> details = <String>[
      annotation.excerpt,
      if (annotation.hasNote) 'Note: ${annotation.note!.trim()}',
      if (annotation.orphaned)
        'The book changed, so this passage cannot be highlighted. '
            'The title and note are kept.',
    ];

    return PaperListTile(
      title: title,
      subtitle: details.join('\n'),
      leading: Icon(
        switch (annotation.kind) {
          AnnotationKind.highlight => Icons.format_quote_outlined,
          AnnotationKind.underline => Icons.format_underline,
          AnnotationKind.note => Icons.sticky_note_2_outlined,
        },
        size: 19,
        color: palette.inkMuted,
      ),
      onTap: onOpen,
      trailing: PopupMenuButton<_AnnotationAction>(
        tooltip: 'Annotation actions',
        icon: const Icon(Icons.more_horiz, size: 18),
        onSelected: (_AnnotationAction action) {
          switch (action) {
            case _AnnotationAction.edit:
              onEdit();
              break;
            case _AnnotationAction.delete:
              onDelete();
              break;
          }
        },
        itemBuilder: (BuildContext context) =>
            const <PopupMenuEntry<_AnnotationAction>>[
              PopupMenuItem<_AnnotationAction>(
                value: _AnnotationAction.edit,
                child: Text('Edit note'),
              ),
              PopupMenuItem<_AnnotationAction>(
                value: _AnnotationAction.delete,
                child: Text('Delete'),
              ),
            ],
      ),
    );
  }
}

enum _AnnotationAction { edit, delete }

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PaperSpace.gutter,
        PaperSpace.lg,
        PaperSpace.gutter,
        PaperSpace.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(title, style: PaperTypography.of(context).heading),
          ),
          PaperButton(label: 'Close', onPressed: onClose),
        ],
      ),
    );
  }
}

class _ReadingSettingsSheet extends ConsumerWidget {
  const _ReadingSettingsSheet({required this.session});

  final ReaderSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);
    final AppSettings settings = ref.watch(settingsProvider);
    final ReaderSettings reader = settings.reader;
    final DisplayPolicy display = ref.watch(displayPolicyProvider);
    // What the reader actually renders with, which differs from the stored
    // values while E-Ink Friendly is active. Showing the stored values here
    // would make the sheet lie about the page it is sitting on.
    final ReaderSettings effective = readerSettingsForDisplay(reader, display);
    final SettingsController controller = ref.read(settingsProvider.notifier);

    // Two kinds of change. Layout settings must reach the open session, which
    // re-paginates in place and keeps the reader's own scroll position; the
    // stored settings are updated first so the re-pagination reads the new
    // value. Everything else only needs persisting.
    Future<void> store(Future<void> Function() write) async {
      await write();
    }

    Future<void> applyLayout(Future<void> Function() write) async {
      await write();
      session.applyReaderSettings();
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PaperSpace.gutter,
                PaperSpace.lg,
                PaperSpace.gutter,
                PaperSpace.sm,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text('Reading', style: type.heading)),
                  PaperButton(
                    label: 'Done',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const PaperRule(strong: true),
            PaperStepper(
              label: 'Text size',
              display: '${(effective.fontSize * 100).round()}%',
              canDecrease: reader.fontSize > 0.85,
              canIncrease: reader.fontSize < 1.6,
              onDecrease: () => applyLayout(
                () => controller.setReaderFontSize(reader.fontSize - 0.05),
              ),
              onIncrease: () => applyLayout(
                () => controller.setReaderFontSize(reader.fontSize + 0.05),
              ),
            ),
            const PaperRule(inset: PaperSpace.gutter),
            PaperStepper(
              label: 'Line spacing',
              display: effective.lineHeight.toStringAsFixed(2),
              canDecrease: reader.lineHeight > 1.25,
              canIncrease: reader.lineHeight < 2.1,
              onDecrease: () => applyLayout(
                () => controller.setReaderLineHeight(reader.lineHeight - 0.05),
              ),
              onIncrease: () => applyLayout(
                () => controller.setReaderLineHeight(reader.lineHeight + 0.05),
              ),
            ),
            const PaperRule(inset: PaperSpace.gutter),
            PaperStepper(
              label: 'Margins',
              display: '${effective.margin.round()} px',
              canDecrease: reader.margin > 12,
              canIncrease: reader.margin < 64,
              onDecrease: () => applyLayout(
                () => controller.setReaderMargin(reader.margin - 4),
              ),
              onIncrease: () => applyLayout(
                () => controller.setReaderMargin(reader.margin + 4),
              ),
            ),
            const PaperRule(inset: PaperSpace.gutter),
            if (session.epubBackend != null) ...<Widget>[
              PaperSettingRow(
                label: 'Flow',
                subtitle: display.isEink
                    ? 'E-Ink Friendly reads in pages. Scrolling returns with '
                          'the Standard profile.'
                    : 'Paged suits e-ink; scrolling suits long sessions.',
                trailing: Wrap(
                  spacing: PaperSpace.xs,
                  children: <Widget>[
                    for (final ReaderFlow flow in ReaderFlow.values)
                      PaperChip(
                        label: flow.label,
                        selected: effective.flow == flow,
                        enabled: !display.isEink,
                        onTap: () =>
                            applyLayout(() => controller.setReaderFlow(flow)),
                      ),
                  ],
                ),
              ),
              const PaperRule(inset: PaperSpace.gutter),
            ],
            PaperSettingRow(
              label: 'Page theme',
              subtitle: 'White, warm paper or inverted ink.',
              trailing: Wrap(
                spacing: PaperSpace.xs,
                children: <Widget>[
                  for (final PaperStyle style in PaperStyle.values)
                    PaperChip(
                      label: style.label,
                      selected: settings.appearance.style == style,
                      onTap: () => store(() => controller.setPaperStyle(style)),
                    ),
                ],
              ),
            ),
            const PaperRule(inset: PaperSpace.gutter),
            PaperSettingRow(
              label: 'Page turns',
              subtitle: display.isEink
                  ? 'E-Ink Friendly uses tap zones. Swipe returns with the '
                        'Standard profile.'
                  : 'Tap zones suit e-ink; swipe suits a scrolling habit.',
              trailing: Wrap(
                spacing: PaperSpace.xs,
                children: <Widget>[
                  for (final PageTurnMode mode in PageTurnMode.values)
                    PaperChip(
                      label: mode.label,
                      selected: effective.turnMode == mode,
                      enabled: !display.isEink,
                      onTap: () => store(() => controller.setTurnMode(mode)),
                    ),
                ],
              ),
            ),
            const PaperRule(inset: PaperSpace.gutter),
            PaperSettingRow(
              label: 'Show page numbers',
              subtitle: 'The position line in the top and bottom bars.',
              trailing: PaperSwitch(
                value: reader.showPageNumbers,
                onChanged: (bool value) =>
                    store(() => controller.setShowPageNumbers(value)),
              ),
            ),
            const PaperRule(inset: PaperSpace.gutter),
            PaperSettingRow(
              label: 'Keep the screen on',
              subtitle: 'Prevents sleep while this document is open.',
              trailing: PaperSwitch(
                value: reader.keepScreenOn,
                onChanged: (bool value) =>
                    store(() => controller.setKeepScreenOn(value)),
              ),
            ),
            const PaperRule(inset: PaperSpace.gutter),
            PaperSettingRow(
              label: 'Serif text',
              subtitle: 'Use the bundled reading face in the reader.',
              trailing: PaperSwitch(
                value: settings.appearance.serifReading,
                onChanged: (bool value) =>
                    applyLayout(() => controller.setSerifReading(value)),
              ),
            ),
            const SizedBox(height: PaperSpace.md),
            Text(
              'Text size, spacing, margins and flow affect TXT and EPUB. A PDF '
              'is drawn exactly as it was authored.',
              style: type.caption.copyWith(color: palette.inkFaint),
            ),
            if (ref.watch(displayPolicyProvider).isEink) ...<Widget>[
              const SizedBox(height: PaperSpace.xs),
              Text(
                'E-Ink Friendly is active: reading is page-only, tap zones are '
                'wider, and text is slightly larger with stronger contrast. '
                'Your stored choices are remembered for Standard.',
                style: type.caption.copyWith(color: palette.inkFaint),
              ),
            ],
            const SizedBox(height: PaperSpace.lg),
          ],
        ),
      ),
    );
  }
}
