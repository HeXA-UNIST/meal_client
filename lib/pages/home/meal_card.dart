import 'package:flutter/material.dart';

import '../../meal.dart';

class MealCard extends StatelessWidget {
  const MealCard({super.key, required this.title, required this.meal});

  final String title;
  final Meal meal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // primaryContainer의 HSL 변환을 한 번만 수행하여 중복 계산 방지
    final primaryHsl = HSLColor.fromColor(theme.colorScheme.primaryContainer);
    final isLight = theme.brightness == Brightness.light;
    final menuTextStyle = theme.textTheme.bodyMedium!.copyWith(height: 1.1);
    final menuLineGap = (menuTextStyle.fontSize ?? 14.0) * 0.65;

    final menuWidgets = <Widget>[];
    for (final menuItem in meal.menu) {
      // Flutter Text는 자동 줄 바꿈과 강제 줄 바꿈의 줄 간격(height)을
      // 구분하지 않아서, 메뉴 항목 간 여백은 SizedBox로 분리해 넣는다.
      if (menuWidgets.isNotEmpty) {
        menuWidgets.add(SizedBox(height: menuLineGap));
      }
      menuWidgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(menuItem, style: menuTextStyle),
        ),
      );
    }

    return Card.filled(
      color: theme.colorScheme.surfaceContainer,
      margin: EdgeInsetsGeometry.all(8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadiusGeometry.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ColoredBox(
            color: primaryHsl
                .withSaturation(0.5)
                .withLightness(isLight ? 0.94 : 0.06)
                .toColor(),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Center(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall!.copyWith(
                    color: primaryHsl
                        .withSaturation(0.8)
                        .withLightness(isLight ? 0.3 : 0.7)
                        .toColor(),
                    fontWeight: FontWeight.w600
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...menuWidgets,
          const SizedBox(height: 8),
          Flexible(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: meal.kcal == null
                    ? const SizedBox()
                    : Text(
                        "${meal.kcal} kcal",
                        style: theme.textTheme.labelMedium!.copyWith(
                            fontSize: 11.5, letterSpacing: 0.1),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
