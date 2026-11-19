import 'package:flutter/material.dart';

/// How a theme draws its background.
enum BackdropKind {
  /// The painted moonlit set (moon, stars, hills, moths). The original look.
  moonlit,

  /// A pre-rendered 3D clay set (an image plate) with live overlays.
  plate,
}

/// Everything that changes between themes.
class StarTheme {
  const StarTheme({
    required this.id,
    required this.name,
    required this.dark,
    required this.bg,
    required this.bg2,
    required this.surface,
    required this.surfaceHi,
    required this.panel,
    required this.text,
    required this.subtext,
    required this.accent,
    required this.accent2,
    required this.cool,
    required this.good,
    required this.danger,
    required this.pebbles,
    this.backdrop = BackdropKind.moonlit,
    this.plate,
    this.blurb = '',
  });

  final String id;
  final String name;
  final bool dark;

  /// Page background, darkest to lighter.
  final Color bg, bg2;

  /// Clay slabs: buttons, cards, chips.
  final Color surface, surfaceHi;

  /// Big clay panels (nav bar, sections).
  final Color panel;
  final Color text, subtext;

  /// Highlights: current song, selected tab, sliders.
  final Color accent;

  /// Strong buttons: play, primary actions.
  final Color accent2;
  final Color cool, good, danger;
  final List<Color> pebbles;
  final BackdropKind backdrop;

  /// Asset folder of the rendered set for [BackdropKind.plate] themes.
  final String? plate;
  final String blurb;

  /// Text color that reads on [accent2] buttons.
  Color get onAccent => accent2.computeLuminance() > 0.45 ? const Color(0xFF1A1410) : const Color(0xFFFFF6E8);
}

const StarTheme kMoonlit = StarTheme(
  id: 'moonlit',
  name: 'Moonlit',
  blurb: 'The original: crooked moon, moths, candle flames.',
  dark: true,
  bg: Color(0xFF0D0A14),
  bg2: Color(0xFF1A1428),
  surface: Color(0xFF34284D),
  surfaceHi: Color(0xFF4A3466),
  panel: Color(0xFF241B35),
  text: Color(0xFFEDE3D0),
  subtext: Color(0xFF9B93A8),
  accent: Color(0xFFF2C14E),
  accent2: Color(0xFFE0782F),
  cool: Color(0xFF8FA9C4),
  good: Color(0xFF55705A),
  danger: Color(0xFFB0405F),
  pebbles: [
    Color(0xFF6F5A8E), Color(0xFF557A8C), Color(0xFF8C5A6E), Color(0xFF5E7A5A),
    Color(0xFF9A6A3E), Color(0xFF4F5F8F), Color(0xFF7E4E5E), Color(0xFF6A7F98),
  ],
);

const StarTheme kGothic = StarTheme(
  id: 'gothic',
  name: 'Gothic Town',
  blurb: 'Crooked spires, glowing windows, a giant moon.',
  dark: true,
  backdrop: BackdropKind.plate,
  plate: 'assets/plates/gothic.jpg',
  bg: Color(0xFF0B0D16),
  bg2: Color(0xFF151A2A),
  surface: Color(0xFF2B2A40),
  surfaceHi: Color(0xFF3C3456),
  panel: Color(0xFF1D1F30),
  text: Color(0xFFEDE6D6),
  subtext: Color(0xFF9DA3B8),
  accent: Color(0xFFF2B85A),
  accent2: Color(0xFFD9682B),
  cool: Color(0xFF7FA6C9),
  good: Color(0xFF4F7A6A),
  danger: Color(0xFFB54663),
  pebbles: [
    Color(0xFF3E5E66), Color(0xFF5E4870), Color(0xFF7A5634), Color(0xFF465072),
    Color(0xFF6B3E4E), Color(0xFF4A6656), Color(0xFF6E6248), Color(0xFF39486A),
  ],
);

const StarTheme kWestern = StarTheme(
  id: 'western',
  name: 'Ghost Town',
  blurb: 'Dusty main street, saloon fronts, a low desert sun.',
  dark: true,
  backdrop: BackdropKind.plate,
  plate: 'assets/plates/western.jpg',
  bg: Color(0xFF1E120C),
  bg2: Color(0xFF2C1A10),
  surface: Color(0xFF5A3420),
  surfaceHi: Color(0xFF74452A),
  panel: Color(0xFF3A2216),
  text: Color(0xFFF6E7D2),
  subtext: Color(0xFFC9A88A),
  accent: Color(0xFFFFB347),
  accent2: Color(0xFFE2552E),
  cool: Color(0xFF8FB3C7),
  good: Color(0xFF6E8B3D),
  danger: Color(0xFFC2453A),
  pebbles: [
    Color(0xFF8A4A26), Color(0xFF6B5A3A), Color(0xFF9A3A24), Color(0xFF5E6A3A),
    Color(0xFF7A6040), Color(0xFF4E5E6E), Color(0xFFA0602E), Color(0xFF6A3A2A),
  ],
);

const StarTheme kSnow = StarTheme(
  id: 'snow',
  name: 'Snow Village',
  blurb: 'Snow-capped cottages and pines on a bright winter day.',
  dark: false,
  backdrop: BackdropKind.plate,
  plate: 'assets/plates/snow.jpg',
  bg: Color(0xFFE6ECF5),
  bg2: Color(0xFFF5F8FC),
  surface: Color(0xFFCAD7E9),
  surfaceHi: Color(0xFFB2C5DF),
  panel: Color(0xFFDCE5F1),
  text: Color(0xFF1F2A3D),
  subtext: Color(0xFF55637C),
  accent: Color(0xFF2E6CB2),
  accent2: Color(0xFFC8442F),
  cool: Color(0xFF4F86C6),
  good: Color(0xFF3F7A5A),
  danger: Color(0xFFC23B3B),
  pebbles: [
    Color(0xFFB34A3A), Color(0xFF4F7CA8), Color(0xFFC79A4E), Color(0xFF6E8A58),
    Color(0xFF8A6AA8), Color(0xFF3F8A8A), Color(0xFFA86A4A), Color(0xFF5A6E9A),
  ],
);

const StarTheme kHarvest = StarTheme(
  id: 'harvest',
  name: 'Harvest',
  blurb: 'Pumpkin patch, red barn, golden afternoon.',
  dark: false,
  backdrop: BackdropKind.plate,
  plate: 'assets/plates/harvest.jpg',
  bg: Color(0xFFF4E7D2),
  bg2: Color(0xFFFBF3E6),
  surface: Color(0xFFE8C9A0),
  surfaceHi: Color(0xFFDCB07C),
  panel: Color(0xFFF0DDC2),
  text: Color(0xFF3A2414),
  subtext: Color(0xFF7A5A40),
  accent: Color(0xFFC85A14),
  accent2: Color(0xFFE07A1F),
  cool: Color(0xFF4C79A8),
  good: Color(0xFF5E7D2E),
  danger: Color(0xFFB23A2A),
  pebbles: [
    Color(0xFFD9772A), Color(0xFFB0452E), Color(0xFFD1A23C), Color(0xFF7E8F3A),
    Color(0xFF9A5A2E), Color(0xFF5A7A9A), Color(0xFFC0602A), Color(0xFF8A6A3A),
  ],
);

/// All themes. The first one is the default.
const List<StarTheme> kThemes = [kMoonlit, kGothic, kWestern, kSnow, kHarvest];

/// The current theme's colors. Static getters so any widget can use them;
/// the app rebuilds from the root when the theme changes.
class Clay {
  static StarTheme current = kMoonlit;

  static Color get night => current.bg;
  static Color get dusk => current.bg2;
  static Color get bruise => current.surface;
  static Color get plum => current.surfaceHi;
  static Color get panel => current.panel;
  static Color get ghost => current.cool;
  static Color get moss => current.good;
  static Color get bone => current.text;
  static Color get ash => current.subtext;
  static Color get candle => current.accent;
  static Color get pumpkin => current.accent2;
  static Color get rose => current.danger;
  static Color get onAccent => current.onAccent;
  static List<Color> get pebbles => current.pebbles;

  static const display = 'MysteryQuest';
  static const storybook = 'IMFell';

  static ThemeData theme() {
    final t = current;
    final brightness = t.dark ? Brightness.dark : Brightness.light;
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: t.surfaceHi,
        brightness: brightness,
        primary: t.accent,
        secondary: t.cool,
        surface: t.bg2,
      ),
      scaffoldBackgroundColor: t.bg,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: t.text.withValues(alpha: 0.05),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: t.text, displayColor: t.text),
      iconTheme: IconThemeData(color: t.text),
      listTileTheme: ListTileThemeData(iconColor: t.text, textColor: t.text),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.surface,
        contentTextStyle: TextStyle(color: t.text),
        behavior: SnackBarBehavior.floating,
        width: 420,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.bg2.withValues(alpha: 0.85),
        hintStyle: TextStyle(color: t.subtext),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: t.bg2, showDragHandle: true),
      dialogTheme: DialogThemeData(backgroundColor: t.bg2),
      popupMenuTheme: PopupMenuThemeData(color: t.bg2, textStyle: TextStyle(color: t.text)),
      scrollbarTheme: ScrollbarThemeData(thumbColor: WidgetStatePropertyAll(t.subtext.withValues(alpha: 0.4))),
    );
  }

  static TextStyle title(double size, {Color? color}) =>
      TextStyle(fontFamily: display, fontSize: size, color: color ?? bone, height: 1.1);

  static TextStyle book(double size, {Color? color}) =>
      TextStyle(fontFamily: storybook, fontSize: size, color: color ?? ash);
}
