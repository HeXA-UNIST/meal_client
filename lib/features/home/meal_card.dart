import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'package:meal_client/main.dart' show mainColor;

// Pretendard w700에서 가장 넓은 숫자('0')와 실사용 최대 자릿수 기준 최악의 경우 문자열.
// 실제 라벨 대신 이걸 측정해야 카드마다 내용이 달라도 항상 같은 축소 배율이 나온다.
const _worstCaseTimeLabel = '06:00 - 08:00';
// Pretendard w600, w500에서는 '4'가 가장 넓음
const _worstCaseKcalText = '1444 kcal';
// cardWidth는 TableCell 전체 폭이므로 Card 바깥 margin과 하단 메타데이터 영역의
// 좌우 padding을 제외해야 Row가 실제로 사용할 수 있는 폭을 얻을 수 있다.
const _cardMargin = 8.0;
const _metadataHorizontalPadding = 16.0;
// 아래 세 값은 폭 측정과 실제 렌더링에서 반드시 같은 값을 써야 한다. 한쪽만
// 바꾸면 계산상으로는 들어맞아도 실제 Row가 넘치거나 필요 이상으로 작아진다.
const _metadataIconSize = 13.0;
const _metadataIconGap = 3.0;
const _metadataKcalGap = 3.0;

// 시스템 글자 크기 설정까지 반영한 실제 렌더링 폭을 얻는다. 고정된 글자 수나
// fontSize만으로 추정하면 접근성 글자 크기에서 계산값과 화면 폭이 달라질 수 있다.
double _measureTextWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  return painter.width;
}

TextStyle _operatingTimeTextStyle(ThemeData theme, Color color) {
  return theme.textTheme.labelMedium!.copyWith(
    color: color,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    height: 1,
  );
}

TextStyle _kcalTextStyle(ThemeData theme) {
  return theme.textTheme.labelMedium!.copyWith(
    fontSize: 11,
    letterSpacing: 0,
    height: 1,
  );
}

double _calculateMetadataScale(
  BuildContext context, {
  required double availableWidth,
}) {
  final theme = Theme.of(context);
  final operatingTimeStyle = _operatingTimeTextStyle(
    theme,
    theme.colorScheme.outline,
  );
  final kcalStyle = _kcalTextStyle(theme);
  // 실제 카드에 운영시간이나 kcal가 없더라도 둘 다 있는 최악의 경우를 기준으로
  // 계산한다. 그래야 데이터 유무에 따라 카드마다 글자 크기가 달라지지 않는다.
  // 색상은 글자 폭에 영향을 주지 않으므로 운영 중이 아닌 기본 색상을 사용한다.
  final naturalWidth =
      _metadataIconSize +
      _metadataIconGap +
      _measureTextWidth(context, _worstCaseTimeLabel, operatingTimeStyle) +
      _metadataKcalGap +
      _measureTextWidth(context, _worstCaseKcalText, kcalStyle);
  return availableWidth >= naturalWidth ? 1.0 : availableWidth / naturalWidth;
}

/// 동일한 폭의 식단 카드들이 공유할 운영시간/칼로리 표시 배율을 계산한다.
///
/// [cardWidth]에는 카드의 외부 margin까지 포함되어 있다. 따라서 margin과 하단
/// 영역의 좌우 padding을 뺀 실제 가용 폭으로 worst-case 조합을 측정한다. 결과는
/// 원래 크기보다 확대되지 않도록 최대 1.0이며, 화면 폭이나 시스템 글자 크기가
/// 바뀌어 상위 위젯이 다시 빌드되면 함께 다시 계산된다.
double calculateMealCardMetadataScale(
  BuildContext context, {
  required double cardWidth,
}) {
  final availableWidth =
      cardWidth - 2 * _cardMargin - 2 * _metadataHorizontalPadding;
  return _calculateMetadataScale(
    context,
    availableWidth: availableWidth.clamp(0.0, double.infinity),
  );
}

/// 같은 레이아웃에 놓인 모든 식단 카드에 공통 메타데이터 배율을 제공한다.
///
/// 개별 [MealCard]에 값을 반복 전달하지 않고 Table 전체를 감싸는 이유는 카드가
/// 생성되는 위치와 실제 레이아웃 위치를 분리하면서도 모든 카드가 정확히 같은
/// 배율에 의존하게 하기 위해서다. 화면 폭 변경으로 [scale]이 달라질 때만 이를
/// 구독한 카드의 메타데이터 영역이 새 값으로 다시 빌드된다.
class MealCardMetadataScaleScope extends InheritedWidget {
  const MealCardMetadataScaleScope({
    super.key,
    required this.scale,
    required super.child,
  });

  final double scale;

  static double? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<MealCardMetadataScaleScope>()
        ?.scale;
  }

  @override
  bool updateShouldNotify(MealCardMetadataScaleScope oldWidget) {
    return scale != oldWidget.scale;
  }
}

// 기본 InkWell은 onLongPress만 넘겨도 손을 대는 즉시(터치 다운) 스플래시가 시작된다.
// 카드 공유는 롱프레스가 실제로 인식된 순간에만 잉크 이펙트가 보이길 원하므로,
// Material의 잉크 컨트롤러에 스플래시를 직접 추가/확정/취소하는 방식으로 구현한다.
// 공유 요청은 OS 팝업 준비를 최대한 빨리 시작하도록 먼저 호출하고, 햅틱은 ink가
// 최초로 그려진 프레임 직후 실행해 시각·촉각 피드백이 함께 느껴지도록 한다.
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
    // 공유 시트는 플랫폼에서 준비하는 시간이 필요하므로 다른 피드백보다 먼저
    // 요청한다. 이 콜백은 Future를 기다리지 않아 이후 ink 생성은 즉시 이어진다.
    widget.onLongPress!();

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

    // ink feature가 등록된 프레임의 페인팅이 끝난 뒤 햅틱을 요청한다. 공유 요청은
    // 이미 시작된 상태이므로 OS 팝업 표시를 인위적으로 늦추지는 않는다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HapticFeedback.lightImpact();
    });
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
    final menuTextStyle = theme.textTheme.bodyMedium!.copyWith(height: 1.15);
    final menuLineGap = (menuTextStyle.fontSize ?? 14.0) * 0.72;
    // 제목이 실제로 있는 첫 섹션에서만 만들고 이후 섹션은 같은 스타일을 재사용한다.
    late final sectionTitleStyle = theme.textTheme.labelSmall!.copyWith(
      fontSize: 10.5,
      color: theme.colorScheme.outline,
      fontWeight: FontWeight.w600,
      height: 1.1,
    );
    // colorScheme.primary는 명암비 확보를 위해 라이트 모드에서 브랜드 그린을
    // 크게 어둡게 눌러버려 (#00CD80 → #006D41) 쨍한 느낌이 사라진다. 브랜드
    // 색상(hue·saturation)은 그대로 유지한 채 밝기만 배경 대비 최소 4.5:1을
    // 만족하는 선에서 조정해 채도를 살린다.
    final operatingTimeColor = isOperating
        ? HSLColor.fromColor(
            mainColor,
          ).withLightness(isLight ? 0.25 : 0.40).toColor()
        : theme.colorScheme.outline;
    final operatingTimeStyle = _operatingTimeTextStyle(
      theme,
      operatingTimeColor,
    );
    final kcalStyle = _kcalTextStyle(theme);
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
              child: Text(sectionTitle, style: sectionTitleStyle),
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
      margin: EdgeInsetsGeometry.all(_cardMargin),
      shape: defaultTargetPlatform == TargetPlatform.iOS
          ? RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(24))
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.16667),
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
                    horizontal: _metadataHorizontalPadding,
                    vertical: 4,
                  ),
                  // 일반 식단 화면에서는 상위 Table이 모든 카드에 같은 배율을
                  // 제공한다. MealCard를 테스트·프리뷰 등에서 단독으로 사용할 때는
                  // Scope가 없으므로 현재 카드의 실제 가용 폭으로 같은 worst-case
                  // 계산을 수행한다. 어느 경로든 하나의 배율을 아이콘·운영시간·
                  // 칼로리에 함께 적용해 요소별 글자 크기가 어긋나지 않게 한다.
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final scale =
                          MealCardMetadataScaleScope.maybeOf(context) ??
                          _calculateMetadataScale(
                            context,
                            availableWidth: constraints.maxWidth,
                          );

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
                                        size: _metadataIconSize * scale,
                                        color: operatingTimeColor,
                                      ),
                                      SizedBox(width: _metadataIconGap * scale),
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
                            SizedBox(width: _metadataKcalGap * scale),
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
