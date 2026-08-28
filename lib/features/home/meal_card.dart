import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/l10n/app_localizations.dart';

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

Color _metadataColor(ThemeData theme) {
  // APCA: 라이트 #5E6B61/#FAFAFA = Lc 75.00,
  // 다크 #CCCCCC/#121212 = Lc -75.10.
  return theme.brightness == Brightness.light
      ? const Color(0xFF5E6B61)
      : const Color(0xFFCCCCCC);
}

Color _activeOperatingTimeColor(ThemeData theme) {
  // 브랜드 hue를 유지하고 OKLCH lightness를 조절했다.
  // APCA: 라이트 #147549/#FAFAFA = Lc 75.19,
  // 다크 #3BE696/#121212 = Lc -75.05.
  return theme.brightness == Brightness.light
      ? const Color(0xFF147549)
      : const Color(0xFF3BE696);
}

Color _sectionTitleColor(ThemeData theme) {
  // 메타데이터보다 초록 기운만 살짝 높이고 작은 제목에 필요한 대비는 유지한다.
  // APCA: 라이트 #506D59/#FAFAFA = Lc 75.58,
  // 다크 #BBD4BE/#121212 = Lc -76.00.
  return theme.brightness == Brightness.light
      ? const Color(0xFF506D59)
      : const Color(0xFFBBD4BE);
}

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
  // 칼로리는 메뉴 본문보다 낮은 위계의 보조 정보이므로, 운영시간 라벨의 기본
  // 색상과 동일한 metadataColor를 사용해 낮은 강조로 표시한다.
  return theme.textTheme.labelMedium!.copyWith(
    color: _metadataColor(theme),
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
    _metadataColor(theme),
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
/// [cardWidth]에는 카드의 외부 margin까지 포함되어 있다. 따라서 실제
/// [horizontalMargin]과 하단 영역의 좌우 padding을 뺀 가용 폭으로 worst-case
/// 조합을 측정한다. 결과는 원래 크기보다 확대되지 않도록 최대 1.0이며, 화면
/// 폭이나 시스템 글자 크기가 바뀌어 상위 위젯이 다시 빌드되면 함께 다시 계산된다.
double calculateMealCardMetadataScale(
  BuildContext context, {
  required double cardWidth,
  double horizontalMargin = 2 * _cardMargin,
}) {
  final availableWidth =
      cardWidth - horizontalMargin - 2 * _metadataHorizontalPadding;
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
    this.margin = const EdgeInsets.all(_cardMargin),
  });

  final String title;
  final Meal meal;
  final String? operatingTimeLabel;
  final bool isOperating;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final languageCode = Localizations.localeOf(context).languageCode;

    // primaryContainer의 HSL 변환을 한 번만 수행하여 중복 계산 방지
    final primaryHsl = HSLColor.fromColor(theme.colorScheme.primaryContainer);
    final isLight = theme.brightness == Brightness.light;
    final metadataColor = _metadataColor(theme);
    // 다크 메뉴 본문: #F5F5F5/#121212 = APCA Lc -100.72.
    final menuTextStyle = theme.textTheme.bodyMedium!.copyWith(
      color: isLight ? null : const Color(0xFFF5F5F5),
      height: 1.135,
    );
    final menuLineGap = (menuTextStyle.fontSize ?? 14.0) * 0.72;
    // 제목이 실제로 있는 첫 섹션에서만 만들고 이후 섹션은 같은 스타일을 재사용한다.
    late final sectionTitleStyle = theme.textTheme.labelSmall!.copyWith(
      fontSize: 10.5,
      color: _sectionTitleColor(theme),
      fontWeight: FontWeight.w600,
      height: 1.1,
    );
    final operatingTimeColor = isOperating
        ? _activeOperatingTimeColor(theme)
        : metadataColor;
    final operatingTimeStyle = _operatingTimeTextStyle(
      theme,
      operatingTimeColor,
    );
    final kcalStyle = _kcalTextStyle(theme);
    final lastSectionKcal = meal.sections.last.kcal;
    final kcalText = lastSectionKcal == null ? null : "$lastSectionKcal kcal";

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

      // 마지막 섹션의 칼로리는 카드 하단에 표시하므로 인라인 대상에서 제외한다.
      final isLastSection = sectionIndex == meal.sections.length - 1;
      final inlineKcalText = isLastSection || section.kcal == null
          ? null
          : "${section.kcal} kcal";

      for (var menuIndex = 0; menuIndex < section.menu.length; menuIndex++) {
        // Flutter Text는 자동 줄 바꿈과 강제 줄 바꿈의 줄 간격(height)을
        // 구분하지 않아서, 메뉴 항목 간 여백은 SizedBox로 분리해 넣는다.
        if (menuIndex > 0) {
          menuWidgets.add(SizedBox(height: menuLineGap));
        }
        final menuItem = section.menu[menuIndex];
        final menuText = Text(
          menuItem.textFor(languageCode),
          style: menuTextStyle,
        );
        final isLastMenuItem = menuIndex == section.menu.length - 1;
        menuWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: isLastMenuItem && inlineKcalText != null
                // Expanded가 칼로리 라벨 폭만큼을 먼저 확보해두므로, 메뉴 텍스트가
                // 길어 칼로리 라벨과 겹칠 경우 자동으로 줄바꿈되어 서로 침범하지
                // 않는다.
                ? Row(
                    // 메뉴 텍스트와 칼로리 텍스트는 폰트 크기·height가 서로
                    // 달라 bounding box 하단(end)을 맞추면 실제 글자 baseline이
                    // 어긋나 보인다. baseline 정렬로 두 텍스트가 같은 줄에 있는
                    // 것처럼 자연스럽게 맞춘다.
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(child: menuText),
                      const SizedBox(width: 8),
                      Text(inlineKcalText, style: kcalStyle),
                    ],
                  )
                : menuText,
          ),
        );
      }
    }

    return Card.filled(
      color: theme.colorScheme.surfaceContainer,
      margin: margin,
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
                      // #006B42 = oklch(0.465091 0.107810 158.53).
                      // sRGB 최대 채도에 가깝고 #E8F7F2에서 APCA Lc 75.26이다.
                      color: isLight
                          ? const Color(0xFF006B42)
                          : primaryHsl
                                .withSaturation(0.8)
                                .withLightness(0.7)
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
