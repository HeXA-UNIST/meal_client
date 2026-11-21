import 'package:material_ui/material_ui.dart';

import 'package:meal_client/l10n/app_localizations.dart';
import 'package:meal_client/domain/meal.dart';

class MealOfDaySwitchButton extends StatelessWidget {
  const MealOfDaySwitchButton({
    super.key,
    required this.onPressed,
    required this.label,
    required this.icon,
  });

  final void Function()? onPressed;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: onPressed,
      label: SizedBox(
        width: 64,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
      icon: Icon(icon),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.comfortable,
        iconColor: colorScheme.onPrimaryContainer,
        backgroundColor: colorScheme.primaryContainer,
        overlayColor: colorScheme.onPrimaryContainer,
      ),
    );
  }
}

class DayOfWeekTabBar extends StatelessWidget implements PreferredSizeWidget {
  const DayOfWeekTabBar({
    super.key,
    required this.tabController,
    this.today,
    this.onTap,
  });

  final TabController tabController;
  final DayOfWeek? today;
  final ValueChanged<int>? onTap;

  static const _preferredSize = Size.fromHeight(44.0);
  static const _indicatorInset = 4.0;

  // 눌림 효과는 숨기되 포커스·호버 강조는 테마 기본값을 사용한다.
  static final _overlayColor = WidgetStateProperty.resolveWith<Color?>((
    states,
  ) {
    if (states.contains(WidgetState.focused) ||
        states.contains(WidgetState.hovered)) {
      return null;
    }
    return Colors.transparent;
  });

  @override
  Size get preferredSize => _preferredSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final directionSign = Directionality.of(context) == TextDirection.rtl
        ? -1.0
        : 1.0;
    final labels = [
      l10n.mon,
      l10n.tue,
      l10n.wed,
      l10n.thu,
      l10n.fri,
      l10n.sat,
      l10n.sun,
    ];

    // APCA 0.0.98G-4g로 실제 surfaceContainer와 계산한 값이다.
    // 라이트: #737373/#FAFAFA = Lc 69.95, 다크: #AAAAAA/#121212 = Lc -55.66.
    final unselectedLabelColor = theme.brightness == Brightness.light
        ? const Color(0xFF737373)
        : const Color(0xFFAAAAAA);

    return PreferredSize(
      preferredSize: _preferredSize,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Material(
            color: colorScheme.surfaceContainer,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: TabBar(
              onTap: onTap,
              tabs: List.generate(labels.length, (index) {
                final isToday = DayOfWeek.values[index] == today;
                // 인디케이터가 바 양 끝 4px 안쪽을 7등분해 그리므로,
                // 각 요일 텍스트도 화면 폭과 무관한 상수만큼 옮겨 알약 중앙에 맞춘다.
                final labelOffset =
                    directionSign *
                    _indicatorInset *
                    (1 - (2 * index + 1) / labels.length);
                return Tab(
                  child: Transform.translate(
                    offset: Offset(labelOffset, 0),
                    child: Text(
                      labels[index],
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      // 오늘인 요일은 w800으로 굵게 표시한다.
                      style: isToday
                          ? const TextStyle(fontWeight: FontWeight.w800)
                          : null,
                    ),
                  ),
                );
              }),
              labelColor: colorScheme.onPrimaryContainer,
              unselectedLabelColor: unselectedLabelColor,
              indicatorSize: TabBarIndicatorSize.tab,
              // 터치·호버 영역은 바의 양 끝까지 채우고, 선택 알약은 상하·양 끝만
              // 4px 안쪽으로 그려 칸마다 폭이 과도하게 좁아지지 않게 한다.
              indicatorPadding: const EdgeInsets.symmetric(
                vertical: _indicatorInset,
              ),
              indicator: _DayOfWeekTabIndicator(
                color: colorScheme.primaryContainer,
                tabCount: labels.length,
                horizontalInset: _indicatorInset,
              ),
              labelStyle: theme.textTheme.titleSmall!.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              labelPadding: EdgeInsets.zero,
              overlayColor: _overlayColor,
              splashFactory: NoSplash.splashFactory,
              splashBorderRadius: BorderRadius.circular(128),
              dividerHeight: 0,
              controller: tabController,
            ),
          ),
        ),
      ),
    );
  }
}

/// 바 양 끝 여백만 [horizontalInset]만큼 비우고 그 안쪽을 [tabCount]등분해
/// 선택 알약을 그리는 인디케이터.
class _DayOfWeekTabIndicator extends Decoration {
  const _DayOfWeekTabIndicator({
    required this.color,
    required this.tabCount,
    required this.horizontalInset,
  });

  final Color color;
  final int tabCount;
  final double horizontalInset;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _DayOfWeekTabIndicatorPainter(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _DayOfWeekTabIndicator &&
          other.color == color &&
          other.tabCount == tabCount &&
          other.horizontalInset == horizontalInset;

  @override
  int get hashCode => Object.hash(color, tabCount, horizontalInset);
}

class _DayOfWeekTabIndicatorPainter extends BoxPainter {
  _DayOfWeekTabIndicatorPainter(this.decoration);

  final _DayOfWeekTabIndicator decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.width <= 0 || size.height <= 0) return;

    final tabWidth = size.width;
    final pillWidth =
        tabWidth - (2 * decoration.horizontalInset) / decoration.tabCount;
    if (pillWidth <= 0) return;

    // 등폭 탭과 TabIndicatorAnimation.linear(TabBarIndicatorSize.tab 기본값)라
    // 전환 중에도 size.width가 일정하다는 전제로 진행 위치를 계산한다.
    final progress = offset.dx / tabWidth;
    final pillRect = Rect.fromLTWH(
      decoration.horizontalInset + progress * pillWidth,
      offset.dy,
      pillWidth,
      size.height,
    );
    final rrect = RRect.fromRectAndRadius(
      pillRect,
      Radius.circular(pillRect.shortestSide / 2),
    );
    canvas.drawRRect(rrect, Paint()..color = decoration.color);
  }
}

class AnimatedDateTitle extends StatelessWidget {
  const AnimatedDateTitle({
    super.key,
    required this.tabController,
    required this.mondayOfWeek,
  });

  final TabController tabController;
  final DateTime mondayOfWeek;

  @override
  Widget build(BuildContext context) {
    // 이 위젯은 언어 변경·주 변경 시에만 rebuild된다.
    // 7개 날짜 문자열을 미리 계산해두면, 아래 AnimatedBuilder가
    // 매 프레임(~60fps)마다 DateTime 연산 + 문자열 포맷을 반복하지 않고
    // 단순 리스트 인덱스 조회만 수행한다.
    final locale = Localizations.localeOf(context);
    final dateLabels = List.generate(DayOfWeek.values.length, (i) {
      final day = mondayOfWeek.add(Duration(days: i));
      return _getLocalizedDate(day.month, day.day, locale);
    });

    final animation = tabController.animation;
    const titleStyle = TextStyle(fontWeight: FontWeight.w700);
    if (animation == null) {
      return Text(dateLabels[tabController.index], style: titleStyle);
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final int displayIndex;
        if (tabController.indexIsChanging) {
          // 요일 탭을 직접 눌러 전환할 때는 목표 탭 날짜를 바로 보여줘서
          // 먼 탭 이동 중 중간 날짜가 순서대로 보이지 않게 한다.
          displayIndex = tabController.index;
        } else {
          // 스와이프 전환은 절반을 넘는 시점부터 다음 요일 날짜를 보여준다.
          displayIndex = animation.value.round().clamp(
            0,
            DayOfWeek.values.length - 1,
          );
        }

        // DateTime 연산·문자열 포맷 없이 미리 계산된 레이블만 조회한다.
        return Text(dateLabels[displayIndex], style: titleStyle);
      },
    );
  }
}

/// 로케일에 따라 월·일을 문자열로 변환한다.
///
/// 한국어: "4월 4일" / 영어: "Apr. 4"
String _getLocalizedDate(int month, int day, Locale locale) {
  final isKorean = locale.languageCode == 'ko';

  const engMonths = [
    'Jan.',
    'Feb.',
    'Mar.',
    'Apr.',
    'May',
    'Jun.',
    'Jul.',
    'Aug.',
    'Sep.',
    'Oct.',
    'Nov.',
    'Dec.',
  ];
  const korMonths = [
    '1월',
    '2월',
    '3월',
    '4월',
    '5월',
    '6월',
    '7월',
    '8월',
    '9월',
    '10월',
    '11월',
    '12월',
  ];

  if (month < 1 || month > 12) {
    throw FormatException('Invalid month: $month');
  }

  final monthStr = isKorean ? korMonths[month - 1] : engMonths[month - 1];
  return isKorean ? '$monthStr $day일' : '$monthStr $day';
}
