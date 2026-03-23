import 'package:flutter/material.dart';

import '../../i18n.dart';
import '../../meal.dart';
import '../../string.dart' as string;

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
        iconColor: colorScheme.onPrimaryContainer,
        backgroundColor: colorScheme.primaryContainer,
        overlayColor: colorScheme.onPrimaryContainer,
      ),
    );
  }
}

class DayOfWeekTabBar extends StatelessWidget implements PreferredSizeWidget {
  DayOfWeekTabBar({
    super.key,
    required this.tabController,
    required this.language,
  });

  final TabController tabController;
  final Language language;

  final _preferredSize = Size.fromHeight(46.0);

  @override
  Size get preferredSize => _preferredSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final unselectedLabelColor = HSLColor.fromColor(colorScheme.onSurface)
        .withSaturation(0)
        .withLightness(theme.brightness == Brightness.light ? 0.6 : 0.4)
        .toColor();

    return PreferredSize(
      preferredSize: _preferredSize,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(128.0),
        ),
        margin: EdgeInsets.symmetric(horizontal: 8.0),
        padding: EdgeInsets.all(4.0),
        child: TabBar(
          tabs: [
            Tab(text: string.mon.getLocalizedString(language), height: 36),
            Tab(text: string.tue.getLocalizedString(language), height: 36),
            Tab(text: string.wed.getLocalizedString(language), height: 36),
            Tab(text: string.thu.getLocalizedString(language), height: 36),
            Tab(text: string.fri.getLocalizedString(language), height: 36),
            Tab(text: string.sat.getLocalizedString(language), height: 36),
            Tab(text: string.sun.getLocalizedString(language), height: 36),
          ],
          labelColor: colorScheme.onPrimaryContainer,
          unselectedLabelColor: unselectedLabelColor,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(128),
          ),
          labelStyle: theme.textTheme.titleSmall!.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          labelPadding: EdgeInsets.zero,
          // resolveWith 대신 all을 사용하여 매 빌드마다
          // 새 클로저를 생성하지 않도록 한다.
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          dividerHeight: 0,
          controller: tabController,
        ),
      ),
    );
  }
}

class AnimatedDateTitle extends StatelessWidget {
  const AnimatedDateTitle({
    super.key,
    required this.tabController,
    required this.mondayOfWeek,
    required this.language,
  });

  final TabController tabController;
  final DateTime mondayOfWeek;
  final Language language;

  @override
  Widget build(BuildContext context) {
    // 이 위젯은 언어 변경·주 변경 시에만 rebuild된다.
    // 7개 날짜 문자열을 미리 계산해두면, 아래 AnimatedBuilder가
    // 매 프레임(~60fps)마다 DateTime 연산 + 문자열 포맷을 반복하지 않고
    // 단순 리스트 인덱스 조회만 수행한다.
    final dateLabels = List.generate(DayOfWeek.values.length, (i) {
      final day = mondayOfWeek.add(Duration(days: i));
      return string.getLocalizedDate(day.month, day.day, language);
    });

    final animation = tabController.animation;
    if (animation == null) {
      return Text(
        dateLabels[tabController.index],
        style: const TextStyle(fontWeight: FontWeight.w700),
      );
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
        return Text(
          dateLabels[displayIndex],
          style: const TextStyle(fontWeight: FontWeight.w700),
        );
      },
    );
  }
}
