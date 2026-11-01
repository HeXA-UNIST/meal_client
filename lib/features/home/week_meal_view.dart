import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/info/app_info.dart';

import 'meal_card.dart';
import 'nested_page_scroll.dart';
import 'resistant_page_motion.dart';
import 'pointer_scroll_session.dart';

const _cardMinWidth = 160;
const _cardMaxWidth = 208;
const _cardOuterMargin = 8.0;
const _cardInnerMargin = 6.0;

String buildMealShareText({
  required String cardTitle,
  required DateTime targetDate,
  required String mealOfDayLabel,
  required Meal meal,
  required String languageCode,
  required String convenienceLabel,
  required String specialLabel,
}) {
  final lines = <String>[
    '[${targetDate.month}/${targetDate.day} $cardTitle $mealOfDayLabel]',
  ];
  for (final section in meal.sections) {
    final sectionTitle = section.titleFor(
      languageCode,
      convenienceLabel: convenienceLabel,
      specialLabel: specialLabel,
    );
    if (sectionTitle != null) {
      lines.add('');
      lines.add('〈$sectionTitle〉');
    }
    lines.addAll(
      section.menu.map((menuItem) => '- ${menuItem.textFor(languageCode)}'),
    );
    final kcal = section.kcal;
    if (kcal != null) {
      lines.add('');
      lines.add('$kcal kcal');
    }
  }
  return lines.join('\n');
}

class WeekMealTabBarView extends StatefulWidget {
  const WeekMealTabBarView({
    super.key,
    required this.weekMeal,
    required this.tabController,
    required this.pageControllerGroup,
    required this.pageCount,
    required this.onPageChanged,
    required this.appInfo,
    required this.mondayOfWeek,
    this.currentKstDateTime,
    this.onNextWeekRequested,
  });

  final WeekMeal weekMeal;
  final TabController tabController;
  final NestedPageScrollControllerGroup pageControllerGroup;
  final int pageCount;
  final void Function(int) onPageChanged;
  final Future<AppInfo> appInfo;
  final DateTime mondayOfWeek;
  final DateTime? currentKstDateTime;
  final Future<void> Function()? onNextWeekRequested;

  @override
  State<WeekMealTabBarView> createState() => _WeekMealTabBarViewState();
}

class _WeekMealTabBarViewState extends State<WeekMealTabBarView> {
  // 일반 페이지 이동과 별도로 관리하는 다음 주 진입 기준.
  static const _weekBoundaryDistance = 120.0;
  final _horizontalMotion = ResistantPageMotion();
  final _pointerSession = PointerScrollSession();
  final _edgeDistance = ValueNotifier<double>(0);

  ScrollPosition? _horizontalPosition;
  bool _horizontalPointerScrolling = false;
  bool _edgeEligible = false;
  bool _openingNextWeek = false;

  @override
  void initState() {
    super.initState();
    widget.tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (widget.tabController.indexIsChanging) {
      _finishHorizontal(cancel: true);
      _pointerSession.reset();
    }
  }

  void _finishHorizontal({
    bool cancel = false,
    bool allowNextWeek = true,
    double velocity = 0,
  }) {
    final openNextWeek =
        !cancel &&
        allowNextWeek &&
        _edgeEligible &&
        _edgeDistance.value >= _weekBoundaryDistance;
    if (_pointerSession.axis == Axis.horizontal) _pointerSession.reset();
    _horizontalPosition = null;
    if (cancel) {
      _horizontalMotion.cancel();
    } else {
      _horizontalMotion.finish(velocity: velocity);
    }
    _horizontalPointerScrolling = false;
    _edgeEligible = false;
    _edgeDistance.value = 0;
    if (openNextWeek) unawaited(_openNextWeek());
  }

  Future<void> _openNextWeek() async {
    final open = widget.onNextWeekRequested;
    if (!mounted || _openingNextWeek || open == null) return;
    setState(() => _openingNextWeek = true);
    try {
      await open();
    } finally {
      if (mounted) {
        _pointerSession.reset();
        setState(() => _openingNextWeek = false);
      }
    }
  }

  void _beginHorizontal(ScrollPosition position) {
    // 일요일로 이동 중 시작된 입력이나 같은 관성으로 다음 주를 열지 않는다.
    final eligible =
        widget.onNextWeekRequested != null &&
        !position.isScrollingNotifier.value &&
        !widget.tabController.indexIsChanging &&
        widget.tabController.index == widget.tabController.length - 1 &&
        (position.pixels - position.maxScrollExtent).abs() < 0.01;
    _finishHorizontal(cancel: true);
    _horizontalPosition = position;
    _edgeEligible = eligible;
  }

  void _startHorizontal(BuildContext context, DragStartDetails details) {
    if (_openingNextWeek) return;
    _pointerSession.reset();
    final position = Scrollable.maybeOf(
      context,
      axis: Axis.horizontal,
    )?.position;
    if (position != null) _beginHorizontal(position);
  }

  void _updateHorizontal(DragUpdateDetails details) {
    final position = _horizontalPosition;
    if (position == null || _openingNextWeek) return;
    final input = axisDirectionIsReversed(position.axisDirection)
        ? details.delta.dx
        : -details.delta.dx;
    var remainingDetails = details;
    if (_edgeEligible) {
      final previous = _edgeDistance.value;
      final distance = (_edgeDistance.value + input)
          .clamp(0.0, _weekBoundaryDistance * 2)
          .toDouble();
      _edgeDistance.value = distance;
      if (distance > 0) return;
      // 안쪽으로 돌아간 세션에서는 주 경계를 다시 시작하지 않는다.
      _edgeEligible = false;
      final remaining = input + previous;
      if (remaining == 0) return;
      final dx = axisDirectionIsReversed(position.axisDirection)
          ? remaining
          : -remaining;
      remainingDetails = DragUpdateDetails(
        sourceTimeStamp: details.sourceTimeStamp,
        delta: Offset(dx, 0),
        primaryDelta: dx,
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
      );
    }
    _horizontalMotion.update(
      position,
      remainingDetails,
      pointerScrolling: _horizontalPointerScrolling,
    );
  }

  void _onPointerSignal(BuildContext context, PointerSignalEvent event) {
    if (event is PointerScrollInertiaCancelEvent) {
      _finishHorizontal(allowNextWeek: false);
      return;
    }
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta;
    if (delta == Offset.zero) return;
    final shifted = HardwareKeyboard.instance.isShiftPressed;
    if (_pointerSession.selectAxis(delta, shifted: shifted) !=
        Axis.horizontal) {
      return;
    }
    final dx = _pointerSession.horizontalDelta(delta);
    final position = Scrollable.maybeOf(
      context,
      axis: Axis.horizontal,
    )?.position;
    if (position == null || !position.hasPixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted) return;
      event.respond(allowPlatformDefault: false);
      if (_openingNextWeek) return;
      if (_horizontalPosition != position) {
        _beginHorizontal(position);
        _pointerSession.selectAxis(delta, shifted: shifted);
      }
      _horizontalPointerScrolling = true;
      _updateHorizontal(
        DragUpdateDetails(
          sourceTimeStamp: event.timeStamp,
          delta: Offset(-dx, 0),
          primaryDelta: -dx,
          globalPosition: event.position,
          localPosition: event.localPosition,
        ),
      );
      _pointerSession.record(_finishHorizontal, boundary: _edgeEligible);
    });
  }

  @override
  void didUpdateWidget(WeekMealTabBarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabController != widget.tabController) {
      _finishHorizontal(cancel: true);
      oldWidget.tabController.removeListener(_onTabChanged);
      widget.tabController.addListener(_onTabChanged);
    }
  }

  @override
  void dispose() {
    _finishHorizontal(cancel: true);
    _pointerSession.reset();
    _edgeDistance.dispose();
    widget.tabController.removeListener(_onTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pages = TabBarView(
      controller: widget.tabController,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(
        widget.tabController.length,
        (tabIndex) => NestedPageScrollView(
          pointerSession: _pointerSession,
          isHorizontalInputActive: () =>
              _horizontalPosition != null || _openingNextWeek,
          onHorizontalPointerSignal: _onPointerSignal,
          onHorizontalDragStart: _startHorizontal,
          onHorizontalDragUpdate: _updateHorizontal,
          onHorizontalDragEnd: (details) =>
              _finishHorizontal(velocity: details.primaryVelocity ?? 0),
          onHorizontalDragCancel: () => _finishHorizontal(allowNextWeek: false),
          controller: widget.pageControllerGroup.getController(tabIndex),
          onPageChanged: (page) {
            // 비활성 요일의 동기화나 늦은 정렬이 끼니 버튼을 덮어쓰지 않게 한다.
            if (widget.tabController.index == tabIndex) {
              widget.onPageChanged(page);
            }
          },
          builder: (context, pageIndex) {
            final nowMeal = widget.weekMeal
                .fromDayOfWeek(DayOfWeek.values[tabIndex])
                .fromMealOfDay(MealOfDay.values[pageIndex]);
            final targetDate = DateUtils.dateOnly(widget.mondayOfWeek)
                .add(Duration(days: tabIndex));
            return FutureBuilder<AppInfo>(
              future: widget.appInfo,
              builder: (context, infoSnapshot) {
                return SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cardCount = Cafeteria.values.fold<int>(
                        0,
                        (count, cafeteria) =>
                            count + nowMeal.fromCafeteria(cafeteria).length,
                      );

                      if (cardCount == 0) {
                        return Center(
                          child: Text(
                            l10n.noMeal,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        );
                      }

                      final double cardWidth;
                      final int columns;
                      final int leftFill;
                      {
                        var divided = (constraints.maxWidth / _cardMaxWidth)
                            .toInt();
                        if (divided < 1) divided = 1;
                        if (divided < 2) {
                          final halfCardWidth = constraints.maxWidth / 2;
                          if (halfCardWidth > _cardMinWidth) {
                            divided = 2;
                            cardWidth = halfCardWidth;
                          } else {
                            cardWidth = constraints.maxWidth < _cardMaxWidth
                                ? constraints.maxWidth
                                : _cardMaxWidth.toDouble();
                          }
                        } else {
                          cardWidth = _cardMaxWidth.toDouble();
                        }

                        if (cardCount <= divided) {
                          columns = cardCount;
                          leftFill = 0;
                        } else {
                          columns = divided;
                          leftFill = (columns - (cardCount / columns).toInt());
                        }
                      }

                      final rowCount = (cardCount + columns - 1) ~/ columns;
                      var cardIndex = 0;
                      final cards = Cafeteria.values
                          .map<Iterable<Widget>>((cafeteria) {
                            final meals = nowMeal.fromCafeteria(cafeteria);
                            return meals.map((meal) {
                              final columnIndex = cardIndex % columns;
                              final rowIndex = cardIndex ~/ columns;
                              cardIndex++;
                              var title = switch (cafeteria) {
                                Cafeteria.dormitory => l10n.dormitoryCafeteria,
                                Cafeteria.student => l10n.studentCafeteria,
                                Cafeteria.faculty => l10n.facultyCafeteria,
                              };

                              // 한식, 할랄 표기는 기숙사 식당에 한정하여 표기한다.
                              if (cafeteria == Cafeteria.dormitory) {
                                final mealType = switch (meal) {
                                  KoreanMeal _ => l10n.menuKorean,
                                  HalalMeal _ => l10n.menuHalal,
                                  _ => null,
                                };
                                if (mealType != null) {
                                  title = l10n.cafeteriaWithMealType(
                                    title,
                                    mealType,
                                  );
                                }
                              }

                              final operatingTime = infoSnapshot
                                  .data
                                  ?.operatingHours
                                  .forDate(targetDate)
                                  .timeFor(
                                    cafeteria,
                                    MealOfDay.values[pageIndex],
                                  );
                              final now =
                                  widget.currentKstDateTime ??
                                  MealTimeConfig.toKst(DateTime.now());
                              final isOperating =
                                  operatingTime != null &&
                                  DateUtils.isSameDay(targetDate, now) &&
                                  operatingTime.contains(now);

                              return MealCard(
                                title: title,
                                meal: meal,
                                // 화면 바깥쪽은 기존 8dp를 유지하고, 카드끼리
                                // 마주 보는 면만 5dp씩 사용해 가로·세로 모두
                                // 카드 사이의 실제 간격을 10dp로 맞춘다.
                                margin: EdgeInsets.fromLTRB(
                                  columnIndex == 0
                                      ? _cardOuterMargin
                                      : _cardInnerMargin,
                                  rowIndex == 0
                                      ? _cardOuterMargin
                                      : _cardInnerMargin,
                                  columnIndex == columns - 1
                                      ? _cardOuterMargin
                                      : _cardInnerMargin,
                                  rowIndex == rowCount - 1
                                      ? _cardOuterMargin
                                      : _cardInnerMargin,
                                ),
                                operatingTimeLabel: operatingTime?.label,
                                isOperating: isOperating,
                                onLongPress: kIsWeb
                                    ? null
                                    : (sharePositionOrigin) {
                                        // 웹 버전에서는 공유 비활성화 (Web Share API 구림)
                                        // 나중에 마우스 호버링으로 클립보드 버튼 띄우기 구현
                                        final languageCode =
                                            Localizations.localeOf(context)
                                                .languageCode;
                                        SharePlus.instance.share(
                                          ShareParams(
                                            sharePositionOrigin:
                                                sharePositionOrigin,
                                            text: buildMealShareText(
                                              cardTitle: title,
                                              targetDate: targetDate,
                                              mealOfDayLabel: switch (MealOfDay
                                                  .values[pageIndex]) {
                                                MealOfDay.breakfast =>
                                                  l10n.breakfast,
                                                MealOfDay.lunch => l10n.lunch,
                                                MealOfDay.dinner => l10n.dinner,
                                              },
                                              meal: meal,
                                              languageCode: languageCode,
                                              convenienceLabel:
                                                  l10n.menuSectionConvenience,
                                              specialLabel:
                                                  l10n.menuSectionSpecial,
                                            ),
                                          ),
                                        );
                                      },
                              );
                            });
                          })
                          .expand((e) => e)
                          .toList(growable: true);
                      for (var i = 0; i < leftFill; i++) {
                        cards.add(const SizedBox());
                      }

                      final rows = (cards.length / columns).toInt();
                      final row = <TableRow>[];
                      for (var i = 0; i < rows; i++) {
                        final end = (i + 1) * columns;
                        row.add(
                          TableRow(
                            children: [
                              const TableCell(child: SizedBox()),
                              ...cards
                                  .sublist(
                                    i * columns,
                                    end < cards.length ? end : cards.length,
                                  )
                                  .map((card) => TableCell(child: card)),
                              const TableCell(child: SizedBox()),
                            ],
                          ),
                        );
                      }
                      final remain = cards
                          .sublist(columns * rows)
                          .map((card) => TableCell(child: card))
                          .toList();
                      if (remain.isNotEmpty) {
                        remain.insert(0, const TableCell(child: SizedBox()));
                        remain.add(const TableCell(child: SizedBox()));
                        row.add(TableRow(children: remain));
                      }

                      // 이 Table의 모든 식단 카드는 FixedColumnWidth(cardWidth)를
                      // 사용하므로 메타데이터 배율도 카드마다 다시 측정할 필요가
                      // 없다. 운영시간과 칼로리가 모두 있는 worst-case 배율을 여기서
                      // 한 번 계산해 Scope로 전달하면, 값이 하나뿐인 카드나 값이 없는
                      // 카드도 동일한 글자 크기와 아이콘 크기를 유지한다.
                      return MealCardMetadataScaleScope(
                        scale: calculateMealCardMetadataScale(
                          context,
                          cardWidth: cardWidth,
                          horizontalMargin: columns == 1
                              ? 2 * _cardOuterMargin
                              : _cardOuterMargin + _cardInnerMargin,
                        ),
                        child: Table(
                          border: const TableBorder(),
                          defaultColumnWidth: FixedColumnWidth(cardWidth),
                          columnWidths: {
                            0: FlexColumnWidth(),
                            columns + 1: FlexColumnWidth(),
                          },
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.intrinsicHeight,
                          children: row,
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
        growable: false,
      ),
    );
    return ValueListenableBuilder<double>(
      valueListenable: _edgeDistance,
      child: pages,
      builder: (context, distance, child) {
        final progress = (distance / _weekBoundaryDistance).clamp(0.0, 1.0);
        final offset = distance / (1 + distance / 80);
        final direction = Directionality.of(context) == TextDirection.rtl
            ? 1.0
            : -1.0;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (distance > 0)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Semantics(
                    label: l10n.nextWeekPreview,
                    child: SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(value: progress),
                    ),
                  ),
                ),
              ),
            Transform.translate(
              offset: Offset(direction * offset, 0),
              child: child,
            ),
          ],
        );
      },
    );
  }
}
