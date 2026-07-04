import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/main.dart' show mainColor;

// Pretendard에서 가장 넓은 숫자('4')와 실사용 최대 자릿수 기준 최악의 경우 문자열.
// 실제 라벨 대신 이걸 측정해야 카드마다 내용이 달라도 항상 같은 축소 배율이 나온다.
const _worstCaseTimeLabel = '04:44 - 04:44';
const _worstCaseKcalText = '1444 kcal';

class MealCard extends StatelessWidget {
  const MealCard({
    super.key,
    required this.title,
    required this.meal,
    this.operatingTimeLabel,
    this.isOperating = false,
  });

  final String title;
  final Meal meal;
  final String? operatingTimeLabel;
  final bool isOperating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // primaryContainer의 HSL 변환을 한 번만 수행하여 중복 계산 방지
    final primaryHsl = HSLColor.fromColor(theme.colorScheme.primaryContainer);
    final isLight = theme.brightness == Brightness.light;
    final menuTextStyle = theme.textTheme.bodyMedium!.copyWith(height: 1.1);
    final menuLineGap = (menuTextStyle.fontSize ?? 14.0) * 0.65;
    // colorScheme.primary는 명암비 확보를 위해 라이트 모드에서 브랜드 그린을
    // 크게 어둡게 눌러버려 (#00CD80 → #006D41) 쨍한 느낌이 사라진다. 브랜드
    // 색상(hue·saturation)은 그대로 유지한 채 밝기만 배경 대비 최소 4.5:1을
    // 만족하는 선에서 조정해 채도를 살린다.
    final operatingTimeColor = isOperating
        ? HSLColor.fromColor(
            mainColor,
          ).withLightness(isLight ? 0.25 : 0.40).toColor()
        : theme.colorScheme.outline;
    final operatingTimeStyle = theme.textTheme.labelMedium!.copyWith(
      color: operatingTimeColor,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      height: 1,
    );
    final kcalStyle = theme.textTheme.labelMedium!.copyWith(
      fontSize: 11,
      letterSpacing: 0,
      height: 1,
    );
    final kcalText = meal.kcal == null ? null : "${meal.kcal} kcal";

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
      shape: defaultTargetPlatform == TargetPlatform.iOS
          ? RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(24))
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                    fontWeight: FontWeight.w600,
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
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                // 글꼴 크기 설정과 디스플레이 크기(DPI) 설정 모두에서 잘리지 않도록,
                // 아이콘·운영시간·칼로리에 필요한 실제 폭을 측정해 하나의 축소
                // 배율을 계산하고 셋 모두에 동일하게 적용한다. 각자 독립적으로
                // FittedBox를 적용하면 여유 폭이 다른 만큼 서로 다른 배율로
                // 줄어들어 글자 크기가 어긋나 보이는 문제가 있었다.
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const iconSize = 13.0;
                    const iconGap = 3.0;
                    const kcalGap = 5.0;

                    double measureWidth(String text, TextStyle style) {
                      final painter = TextPainter(
                        text: TextSpan(text: text, style: style),
                        textDirection: TextDirection.ltr,
                        textScaler: MediaQuery.textScalerOf(context),
                      )..layout();
                      return painter.width;
                    }

                    var naturalWidth = 0.0;
                    if (operatingTimeLabel != null) {
                      naturalWidth +=
                          iconSize +
                          iconGap +
                          measureWidth(_worstCaseTimeLabel, operatingTimeStyle);
                    }
                    if (kcalText != null) {
                      if (operatingTimeLabel != null) naturalWidth += kcalGap;
                      naturalWidth += measureWidth(
                        _worstCaseKcalText,
                        kcalStyle,
                      );
                    }

                    final scale = naturalWidth <= constraints.maxWidth
                        ? 1.0
                        : constraints.maxWidth / naturalWidth;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: operatingTimeLabel == null
                              ? const SizedBox()
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(
                                      // 운영 여부를 색상뿐 아니라 아이콘 모양으로도
                                      // 구분해 색각 이상 사용자도 상태를 알 수 있게 한다.
                                      isOperating
                                          ? Icons.restaurant
                                          : Icons.access_time,
                                      size: iconSize * scale,
                                      color: operatingTimeColor,
                                    ),
                                    SizedBox(width: iconGap * scale),
                                    Flexible(
                                      child: Text(
                                        operatingTimeLabel!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: operatingTimeStyle.copyWith(
                                          fontSize:
                                              operatingTimeStyle.fontSize! *
                                              scale,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        if (kcalText != null) SizedBox(width: kcalGap * scale),
                        if (kcalText != null)
                          Text(
                            kcalText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: kcalStyle.copyWith(
                              fontSize: kcalStyle.fontSize! * scale,
                            ),
                          ),
                      ],
                    );
                  },
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
