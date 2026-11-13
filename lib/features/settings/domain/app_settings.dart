import 'package:flutter/foundation.dart';

import '../../../core/display/display_profile.dart';
import '../../../theme/paper_palette.dart';

/// Which block of Paper Home is visible.
///
/// This is a real preference: the corresponding widget is not built at all
/// when its section is hidden, which is both the promised behaviour and the
/// cheaper one.
enum HomeSection {
  continueReading('continue', 'Continue reading'),
  today('today', 'Today'),
  recent('recent', 'Recent documents'),
  search('search', 'Search');

  const HomeSection(this.id, this.label);

  final String id;
  final String label;
}

/// Vertical rhythm of Paper Home.
///
/// Density changes spacing, not type size: the interface text scale remains the
/// one accessibility control for how large text is. A second "launcher text
/// scale" would give two controls that fight over the same pixels.
enum HomeDensity {
  comfortable('comfortable', 'Comfortable'),
  compact('compact', 'Compact');

  const HomeDensity(this.id, this.label);

  final String id;
  final String label;

  static HomeDensity fromId(String? id) {
    for (final HomeDensity density in HomeDensity.values) {
      if (density.id == id) return density;
    }
    return HomeDensity.comfortable;
  }
}

/// How the reader lays out a reflowable document.
enum ReaderFlow {
  paged('paged', 'Paged'),
  scroll('scroll', 'Scrolling');

  const ReaderFlow(this.id, this.label);

  final String id;
  final String label;

  static ReaderFlow fromId(String? id) {
    for (final ReaderFlow flow in ReaderFlow.values) {
      if (flow.id == id) return flow;
    }
    return ReaderFlow.paged;
  }
}

/// How page turns are triggered in the reader.
enum PageTurnMode {
  /// Tap the left/right third of the page. The default: no chrome, no gesture
  /// learning, works on e-ink where a swipe is a full-screen refresh.
  tap('tap', 'Tap zones'),

  /// Swipe horizontally, like a scroll.
  swipe('swipe', 'Swipe'),

  /// Both.
  both('both', 'Tap and swipe');

  const PageTurnMode(this.id, this.label);

  final String id;
  final String label;

  static PageTurnMode fromId(String? id) {
    for (final PageTurnMode mode in PageTurnMode.values) {
      if (mode.id == id) return mode;
    }
    return PageTurnMode.tap;
  }
}

/// Every user preference in PaperOS, as one immutable value.
///
/// Grouped into records so that a change to one area does not dirty the whole
/// object, and so the Settings screen can be written declaratively.
@immutable
class AppearanceSettings {
  const AppearanceSettings({
    this.style = PaperStyle.white,
    this.textScale = 1,
    this.serifReading = true,
  });

  final PaperStyle style;

  /// Multiplier on the whole type scale: 0.9, 1.0, 1.1, 1.25.
  final double textScale;
  final bool serifReading;

  AppearanceSettings copyWith({
    PaperStyle? style,
    double? textScale,
    bool? serifReading,
  }) {
    return AppearanceSettings(
      style: style ?? this.style,
      textScale: textScale ?? this.textScale,
      serifReading: serifReading ?? this.serifReading,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'style': style.id,
    'textScale': textScale,
    'serifReading': serifReading,
  };

  static AppearanceSettings fromJson(Map<String, Object?> json) {
    return AppearanceSettings(
      style: PaperStyle.fromId(json['style'] as String?),
      textScale: (json['textScale'] as num?)?.toDouble() ?? 1,
      serifReading: (json['serifReading'] as bool?) ?? true,
    );
  }
}

@immutable
class ReaderSettings {
  const ReaderSettings({
    this.fontSize = 1,
    this.lineHeight = 1.62,
    this.margin = 24,
    this.turnMode = PageTurnMode.tap,
    this.flow = ReaderFlow.paged,
    this.showPageNumbers = true,
    this.keepScreenOn = false,
  });

  /// Multiplier applied to the reader body size: 0.85 .. 1.6.
  final double fontSize;
  final double lineHeight;

  /// Horizontal page margin in logical pixels.
  final double margin;
  final PageTurnMode turnMode;

  /// Reflowable formats can be read page-by-page or as one continuous scroll.
  /// PDFs stay paged because their native renderer is page-oriented.
  final ReaderFlow flow;
  final bool showPageNumbers;
  final bool keepScreenOn;

  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    double? margin,
    PageTurnMode? turnMode,
    ReaderFlow? flow,
    bool? showPageNumbers,
    bool? keepScreenOn,
  }) {
    return ReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      margin: margin ?? this.margin,
      turnMode: turnMode ?? this.turnMode,
      flow: flow ?? this.flow,
      showPageNumbers: showPageNumbers ?? this.showPageNumbers,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'margin': margin,
    'turnMode': turnMode.id,
    'flow': flow.id,
    'showPageNumbers': showPageNumbers,
    'keepScreenOn': keepScreenOn,
  };

  static ReaderSettings fromJson(Map<String, Object?> json) {
    return ReaderSettings(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 1,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.62,
      margin: (json['margin'] as num?)?.toDouble() ?? 24,
      turnMode: PageTurnMode.fromId(json['turnMode'] as String?),
      flow: ReaderFlow.fromId(json['flow'] as String?),
      showPageNumbers: (json['showPageNumbers'] as bool?) ?? true,
      keepScreenOn: (json['keepScreenOn'] as bool?) ?? false,
    );
  }
}

@immutable
class LauncherSettings {
  const LauncherSettings({
    this.showIcons = true,
    this.showSystemApps = false,
    this.showRecents = true,
    this.favoritePackages = const <String>[],
    this.recentPackages = const <String>[],
  });

  /// Maximum number of remembered launches.
  ///
  /// Recents are a convenience strip, not a usage log: a bounded list keeps the
  /// drawer stable and means the stored settings document cannot grow without
  /// limit as apps are opened over months.
  static const int maxRecents = 8;

  /// Show the real launcher icon next to each app in the app drawer.
  final bool showIcons;

  /// Include preinstalled system apps in the drawer.
  final bool showSystemApps;

  /// Show the recently launched strip at the top of the drawer.
  final bool showRecents;

  /// Ordered package names pinned to the top of the drawer.
  final List<String> favoritePackages;

  /// Package names launched most recently, newest first, at most
  /// [maxRecents]. Stored beside favourites so one settings document remains
  /// the single source of launcher preferences.
  final List<String> recentPackages;

  LauncherSettings copyWith({
    bool? showIcons,
    bool? showSystemApps,
    bool? showRecents,
    List<String>? favoritePackages,
    List<String>? recentPackages,
  }) {
    return LauncherSettings(
      showIcons: showIcons ?? this.showIcons,
      showSystemApps: showSystemApps ?? this.showSystemApps,
      showRecents: showRecents ?? this.showRecents,
      favoritePackages: favoritePackages ?? this.favoritePackages,
      recentPackages: recentPackages ?? this.recentPackages,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'showIcons': showIcons,
    'showSystemApps': showSystemApps,
    'showRecents': showRecents,
    'favoritePackages': favoritePackages,
    'recentPackages': recentPackages,
  };

  static LauncherSettings fromJson(Map<String, Object?> json) {
    List<String> packages(String key) {
      final Object? raw = json[key];
      return raw is List
          ? raw.whereType<String>().toList(growable: false)
          : const <String>[];
    }

    return LauncherSettings(
      showIcons: (json['showIcons'] as bool?) ?? true,
      showSystemApps: (json['showSystemApps'] as bool?) ?? false,
      showRecents: (json['showRecents'] as bool?) ?? true,
      favoritePackages: packages('favoritePackages'),
      recentPackages: packages('recentPackages')
          .take(maxRecents)
          .toList(growable: false),
    );
  }
}

@immutable
class HomeSettings {
  const HomeSettings({
    this.hiddenSections = const <HomeSection>{},
    this.showClock = true,
    this.showDate = true,
    this.density = HomeDensity.comfortable,
  });

  final Set<HomeSection> hiddenSections;
  final bool showClock;

  /// Show the long date under the clock. Independent of the clock so an e-ink
  /// home screen can keep the date while dropping a seconds-resolution clock.
  final bool showDate;

  /// Spacing used between Paper Home blocks.
  final HomeDensity density;

  bool shows(HomeSection section) => !hiddenSections.contains(section);

  HomeSettings copyWith({
    Set<HomeSection>? hiddenSections,
    bool? showClock,
    bool? showDate,
    HomeDensity? density,
  }) {
    return HomeSettings(
      hiddenSections: hiddenSections ?? this.hiddenSections,
      showClock: showClock ?? this.showClock,
      showDate: showDate ?? this.showDate,
      density: density ?? this.density,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'hiddenSections': hiddenSections
        .map((HomeSection s) => s.id)
        .toList(growable: false),
    'showClock': showClock,
    'showDate': showDate,
    'density': density.id,
  };

  static HomeSettings fromJson(Map<String, Object?> json) {
    final Object? raw = json['hiddenSections'];
    final Set<HomeSection> hidden = <HomeSection>{};
    if (raw is List) {
      for (final Object? value in raw) {
        for (final HomeSection section in HomeSection.values) {
          if (section.id == value) hidden.add(section);
        }
      }
    }
    return HomeSettings(
      hiddenSections: hidden,
      showClock: (json['showClock'] as bool?) ?? true,
      showDate: (json['showDate'] as bool?) ?? true,
      density: HomeDensity.fromId(json['density'] as String?),
    );
  }
}

/// Display-profile preference.
@immutable
class DisplaySettings {
  const DisplaySettings({this.profile = DisplayProfile.standard});

  final DisplayProfile profile;

  DisplaySettings copyWith({DisplayProfile? profile}) {
    return DisplaySettings(profile: profile ?? this.profile);
  }

  Map<String, Object?> toJson() => <String, Object?>{'profile': profile.id};

  static DisplaySettings fromJson(Map<String, Object?> json) {
    return DisplaySettings(
      profile: DisplayProfile.fromId(json['profile'] as String?),
    );
  }
}

/// Root settings value.
@immutable
class AppSettings {
  const AppSettings({
    this.appearance = const AppearanceSettings(),
    this.reader = const ReaderSettings(),
    this.launcher = const LauncherSettings(),
    this.home = const HomeSettings(),
    this.display = const DisplaySettings(),
    this.askOnExit = true,
  });

  final AppearanceSettings appearance;
  final ReaderSettings reader;
  final LauncherSettings launcher;
  final HomeSettings home;
  final DisplaySettings display;

  /// Confirm before leaving a modified note or document deletion. Every
  /// destructive action in PaperOS asks; nothing deletes silently.
  final bool askOnExit;

  const AppSettings.defaults()
    : appearance = const AppearanceSettings(),
      reader = const ReaderSettings(),
      launcher = const LauncherSettings(),
      home = const HomeSettings(),
      display = const DisplaySettings(),
      askOnExit = true;

  AppSettings copyWith({
    AppearanceSettings? appearance,
    ReaderSettings? reader,
    LauncherSettings? launcher,
    HomeSettings? home,
    DisplaySettings? display,
    bool? askOnExit,
  }) {
    return AppSettings(
      appearance: appearance ?? this.appearance,
      reader: reader ?? this.reader,
      launcher: launcher ?? this.launcher,
      home: home ?? this.home,
      display: display ?? this.display,
      askOnExit: askOnExit ?? this.askOnExit,
    );
  }

  /// The settings document stored locally and inside a `.paperosbackup`.
  ///
  /// Unknown future fields are not preserved here; backups declare the exact
  /// schema they were produced by, and an unknown newer schema is refused.
  Map<String, Object?> toJson() => <String, Object?>{
    'appearance': appearance.toJson(),
    'reader': reader.toJson(),
    'launcher': launcher.toJson(),
    'home': home.toJson(),
    'display': display.toJson(),
    'askOnExit': askOnExit,
  };

  static AppSettings fromJson(Map<String, Object?> json) {
    Map<String, Object?> section(String key) {
      final Object? value = json[key];
      if (value is Map<String, Object?>) return value;
      if (value is Map) return value.cast<String, Object?>();
      return const <String, Object?>{};
    }

    return AppSettings(
      appearance: AppearanceSettings.fromJson(section('appearance')),
      reader: ReaderSettings.fromJson(section('reader')),
      launcher: LauncherSettings.fromJson(section('launcher')),
      home: HomeSettings.fromJson(section('home')),
      display: DisplaySettings.fromJson(section('display')),
      askOnExit: (json['askOnExit'] as bool?) ?? true,
    );
  }
}
