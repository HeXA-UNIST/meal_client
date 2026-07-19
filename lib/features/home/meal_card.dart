import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'package:meal_client/main.dart' show mainColor;

// Pretendard w700에서 가장 넓은 숫자('0')와 실사용 최대 자릿수 기준 최악의 경우 문자열.
// 실제 라벨 대신 이걸 측정해야 카드마다 내용이 달라도 항상 같은 축소 배율이 나온다.
const _worstCaseTimeLabel = '06:00 - 08:00';
// Pretendard w600, w500에서는 '4'가 가장 넓음
const _worstCaseKcalText = '1444 kcal';

// 기본 InkWell은 onLongPress만 넘겨도 손을 대는 즉시(터치 다운) 스플래시가 시작된다.
// 카드 공유는 롱프레스가 실제로 인식된 순간에만 잉크 이펙트가 보이길 원하므로,
// Material의 잉크 컨트롤러에 스플래시를 직접 추가/확정/취소하는 방식으로 구현한다.
class _LongPressSplash extends StatefulWidget {
  const _LongPressSplash({required this.onLongPress, required this.child});

  final VoidCallback? onLongPress;
  final Widget child;

  @override
  State<_LongPressSplash> createState() => _LongPressSplashState();
}

class _LongPressSplashState extends State<_LongPressSplash> {
  InteractiveInkFeature? _splash;

  void _handleLongPressStart(LongPressStartDetails details) {
    final referenceBox = context.findRenderObject()! as RenderBox;
    final theme = Theme.of(context);
    _splash = theme.splashFactory.create(
      controller: Material.of(context),
      referenceBox: referenceBox,
      position: details.localPosition,
      color: theme.splashColor,
      textDirection: Directionality.of(context),
      containedInkWell: true,
      rectCallback: () => Offset.zero & referenceBox.size,
      onRemoved: () => _splash = null,
    );
    widget.onLongPress!();
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    _splash?.confirm();
    _splash = null;
  }

  void _handleLongPressCancel() {
    _splash?.cancel();
    _splash = null;
  }

  @override
  Widget build(BuildContext context) {
    final onLongPress = widget.onLongPress;
    return GestureDetector(
      // deferToChild(기본값)로는 Column 내부의 빈 여백·패딩 영역이 히트 테스트를
      // 통과하지 못해 롱프레스 자체가 인식되지 않는다. InkWell도 내부적으로
      // opaque를 사용하므로 카드 전체 영역에서 반응하도록 맞춘다.
      behavior: HitTestBehavior.opaque,
      onLongPressStart: onLongPress == null ? null : _handleLongPressStart,
      onLongPressEnd: onLongPress == null ? null : _handleLongPressEnd,
      onLongPressCancel: onLongPress == null ? null : _handleLongPressCancel,
      child: widget.child,
    );
  }
}

class MealCard extends StatelessWidget {
  const MealCard({
    super.key,
    required this.title,
    required this.meal,
    this.operatingTimeLabel,
    this.isOperating = false,
    this.onLongPress,
  });

  final String title;
  final Meal meal;
  final String? operatingTimeLabel;
  final bool isOperating;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final languageCode = Localizations.localeOf(context).languageCode;

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
    for (
      var sectionIndex = 0;
      sectionIndex < meal.sections.length;
      sectionIndex++
    ) {
      final section = meal.sections[sectionIndex];
      if (sectionIndex > 0) {
        menuWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Divider(
              height: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant,
            ),
          ),
        );
      }

      final sectionTitle = section.titleFor(
        languageCode,
        convenienceLabel: l10n.menuSectionConvenience,
        specialLabel: l10n.menuSectionSpecial,
      );
      if (sectionTitle != null) {
        menuWidgets.add(
          Padding(
            padding: EdgeInsets.fromLTRB(16, sectionIndex == 0 ? 8 : 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                sectionTitle,
                style: theme.textTheme.labelSmall!.copyWith(
                  color: theme.colorScheme.outline,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ),
          ),
        );
      } else if (sectionIndex == 0) {
        menuWidgets.add(const SizedBox(height: 8));
      }

      for (var menuIndex = 0; menuIndex < section.menu.length; menuIndex++) {
        // Flutter Text는 자동 줄 바꿈과 강제 줄 바꿈의 줄 간격(height)을
        // 구분하지 않아서, 메뉴 항목 간 여백은 SizedBox로 분리해 넣는다.
        if (menuIndex > 0) {
          menuWidgets.add(SizedBox(height: menuLineGap));
        }
        final menuItem = section.menu[menuIndex];
        menuWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(menuItem.textFor(languageCode), style: menuTextStyle),
          ),
        );
      }
    }

    return Card.filled(
      color: theme.colorScheme.surfaceContainer,
      margin: EdgeInsetsGeometry.all(8),
      shape: defaultTargetPlatform == TargetPlatform.iOS
          ? RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(24))
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.125),
      surfaceTintColor: Colors.transparent,
      child: _LongPressSplash(
        onLongPress: onLongPress,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ColoredBox 대신 Ink를 사용: ColoredBox는 일반 자식으로 그려져
            // Material의 잉크 스플래시보다 항상 위에 칠해지므로 타이틀 바
            // 영역에서 롱프레스 효과가 가려진다. Ink는 배경을 Material의
            // 잉크 피처로 등록해 스플래시와 같은 레이어에서 그려지게 한다.
            Ink(
              color: primaryHsl
                  .withSaturation(0.5)
                  .withLightness(isLight ? 0.94 : 0.06)
                  .toColor(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 16,
                ),
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
                            measureWidth(
                              _worstCaseTimeLabel,
                              operatingTimeStyle,
                            );
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
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
                          if (kcalText != null)
                            SizedBox(width: kcalGap * scale),
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
      ),
    );
  }
}
