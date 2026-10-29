import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../config/app_config.dart';
import '../../../core/errors/paper_exception.dart';
import '../../../core/platform/keep_awake_service.dart';
import '../../../core/platform/pdf_service.dart';
import '../../../shared/widgets/paper_widgets.dart';
import '../../../theme/paper_palette.dart';
import '../../../theme/paper_space.dart';
import '../../../theme/paper_typography.dart';
import '../../library/domain/document.dart';
import '../../settings/application/settings_controller.dart';
import '../../settings/domain/app_settings.dart';
import '../application/reader_controller.dart';
import '../domain/reader_backend.dart';
import '../domain/text_paginator.dart';

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
  void _armChromeTimer(bool chromeVisible) {
    _chromeTimer?.cancel();
    if (!chromeVisible) return;
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
    final ReaderSettings settings = ref.watch(settingsProvider).reader;
    final bool showNumbers = settings.showPageNumbers;

    _syncKeepAwake(settings.keepScreenOn);
    _armChromeTimer(state.chromeVisible);

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
          _ReaderTopBar(
            state: state,
            visible: state.chromeVisible,
            showPageNumbers: showNumbers,
            onBack: () => Navigator.of(context).maybePop(),
            onBookmarks: () => _showBookmarks(state),
            onSettings: _showReadingSettings,
          ),
          _ReaderBottomBar(
            state: state,
            visible: state.chromeVisible,
            onPrevious: () => _turn(previous: true),
            onNext: () => _turn(previous: false),
            onGoToPage: () => _promptForPage(state),
            onToggleBookmark: () => _toggleBookmark(state),
          ),
        ],
      ),
    );
  }

  void _onViewport(Size size) {
    if (size.isEmpty || size == _pageViewport) return;
    _pageViewport = size;
    _reportedViewport = true;
    // Text pagination is measured against the page area, which is only known
    // after the first layout, so the session is told about it a frame later.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _session.setViewport(size);
    });
  }

  void _onTapZone(Offset position, Size size) {
    _session.onInteraction();
    final double fraction = size.width <= 0 ? 0.5 : position.dx / size.width;
    if (fraction < 0.3) {
      _turn(previous: true);
    } else if (fraction > 0.7) {
      _turn(previous: false);
    } else {
      _toggleChrome();
    }
  }

  void _onSwipe(DragEndDetails details) {
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
      backgroundColor: paperPalette(context).canvas,
      barrierColor: paperPalette(context).ink.withValues(alpha: 0.32),
      shape: const RoundedRectangleBorder(),
      builder: (BuildContext sheetContext) {
        return _BookmarksSheet(state: state);
      },
    );
  }

  /// Reading settings are edited in place: every change re-paginates the text
  /// immediately, so the user sees the effect of a font size without leaving
  /// the document.
  Future<void> _showReadingSettings() async {
    await showModalBottomSheet<void>(
      context: context,
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
    // Report the initial viewport as soon as a frame exists, so a text
    // document opened directly does not show a single un-paginated screen.
    if (!_reportedViewport) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _pageViewport != Size.zero) return;
        _session.setViewport(_pageViewport);
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
    final PageTurnMode mode = widget.settings.turnMode;
    final EdgeInsets chromeInset = EdgeInsets.only(
      top: kReaderTopBarHeight + MediaQuery.paddingOf(context).top,
      bottom: kReaderBottomBarHeight + MediaQuery.paddingOf(context).bottom,
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
        if (mode != PageTurnMode.tap) {
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

class _ReaderTopBar extends StatelessWidget {
  const _ReaderTopBar({
    required this.state,
    required this.visible,
    required this.showPageNumbers,
    required this.onBack,
    required this.onBookmarks,
    required this.onSettings,
  });

  final ReaderState state;
  final bool visible;
  final bool showPageNumbers;
  final VoidCallback onBack;
  final VoidCallback onBookmarks;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);

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
                        state.backend.positionLabel,
                        style: type.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onBookmarks,
                icon: const Icon(Icons.bookmarks_outlined),
                tooltip: 'Bookmarks (${state.bookmarks.length})',
              ),
              IconButton(
                onPressed: onSettings,
                icon: const Icon(Icons.text_fields),
                tooltip: 'Reading settings',
              ),
              const SizedBox(width: PaperSpace.xs),
            ],
          ),
        ),
      ),
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
    final bool first = state.pageIndex <= 0;
    final bool last = state.pageIndex >= state.pageCount - 1;

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
                    tooltip: 'Previous page',
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
                                  state.backend.positionLabel,
                                  style: type.meta,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!state.backend.isPageCountExact) ...<Widget>[
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
                    tooltip: 'Next page',
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
    return AnimatedSlide(
      offset: visible ? Offset.zero : Offset(0, fromTop ? -1 : 1),
      duration: const Duration(milliseconds: 140),
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

/// Reading settings, applied to the open document as they change.
class _ReadingSettingsSheet extends ConsumerWidget {
  const _ReadingSettingsSheet({required this.session});

  final ReaderSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);
    final AppSettings settings = ref.watch(settingsProvider);
    final ReaderSettings reader = settings.reader;
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
              display: '${(reader.fontSize * 100).round()}%',
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
              display: reader.lineHeight.toStringAsFixed(2),
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
              display: '${reader.margin.round()} px',
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
            PaperSettingRow(
              label: 'Page turns',
              subtitle: 'Tap zones suit e-ink; swipe suits a scrolling habit.',
              trailing: Wrap(
                spacing: PaperSpace.xs,
                children: <Widget>[
                  for (final PageTurnMode mode in PageTurnMode.values)
                    PaperChip(
                      label: mode.label,
                      selected: reader.turnMode == mode,
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
              'Text size and margins only affect plain text files. A PDF is '
              'drawn exactly as it was authored.',
              style: type.caption.copyWith(color: palette.inkFaint),
            ),
            const SizedBox(height: PaperSpace.lg),
          ],
        ),
      ),
    );
  }
}
