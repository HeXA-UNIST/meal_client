import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'meal_card.dart';
import 'nested_page_scroll.dart';

const _cardMinWidth = 160;
const _cardMaxWidth = 208;

String buildMealShareText({
  required String cardTitle,
  required Meal meal,
  required String languageCode,
  required String convenienceLabel,
  required String specialLabel,
}) {
  final lines = <String>['[$cardTitle]'];
  for (final section in meal.sections) {
    final sectionTitle = section.titleFor(
      languageCode,
      convenienceLabel: convenienceLabel,
      specialLabel: specialLabel,
    );
    if (sectionTitle != null) {
      lines.add('');
      lines.add('[$sectionTitle]');
    }
    lines.addAll(
      section.menu.map((menuItem) => '- ${menuItem.textFor(languageCode)}'),
    );
  }
  final kcal = meal.kcal;
  if (kcal != null) {
    lines.add('');
    lines.add('$kcal kcal');
  }
  return lines.join('\n');
}

class WeekMealTabBarView extends StatelessWidget {
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
  });

  final WeekMeal weekMeal;
  final TabController tabController;
  final NestedPageScrollControllerGroup pageControllerGroup;
  final int pageCount;
  final void Function(int) onPageChanged;
  final Future<AppInfo> appInfo;
  final DateTime mondayOfWeek;
  final DateTime? currentKstDateTime;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TabBarView(
      controller: tabController,
      children: List.generate(
        tabController.length,
        (tabIndex) => NestedPageScrollView(
          controller: pageControllerGroup.getController(tabIndex),
          onPageChanged: onPageChanged,
          builder: (context, pageIndex) {
            final nowMeal = weekMeal
                .fromDayOfWeek(DayOfWeek.values[tabIndex])
                .fromMealOfDay(MealOfDay.values[pageIndex]);
            final targetDate = DateUtils.dateOnly(
              mondayOfWeek,
            ).add(Duration(days: tabIndex));
            return FutureBuilder<AppInfo>(
              future: appInfo,
              builder: (context, infoSnapshot) {
                return SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cards = Cafeteria.values
                          .map<Iterable<Widget>>((cafeteria) {
                            final meals = nowMeal.fromCafeteria(cafeteria);
                            return meals.map((meal) {
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
                                  currentKstDateTime ??
                                  MealTimeConfig.toKst(DateTime.now());
                              final isOperating =
                                  operatingTime != null &&
                                  DateUtils.isSameDay(targetDate, now) &&
                                  operatingTime.contains(now);

                              return MealCard(
                                title: title,
                                meal: meal,
                                operatingTimeLabel: operatingTime?.label,
                                isOperating: isOperating,
                                onLongPress: kIsWeb
                                    ? null
                                    : () {
                                        // 웹 버전에서는 공유 비활성화 (Web Share API 구림)
                                        // 나중에 마우스 호버링으로 클립보드 버튼 띄우기 구현
                                        final languageCode =
                                            Localizations.localeOf(
                                              context,
                                            ).languageCode;
                                        HapticFeedback.lightImpact();
                                        SharePlus.instance.share(
                                          ShareParams(
                                            text: buildMealShareText(
                                              cardTitle: title,
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

                      if (cards.isEmpty) {
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
                        if (divided < 2) {
                          final halfCardWidth = constraints.maxWidth / 2;
                          if (halfCardWidth > _cardMinWidth) {
                            divided = 2;
                            cardWidth = halfCardWidth;
                          } else {
                            cardWidth = _cardMaxWidth.toDouble();
                          }
                        } else {
                          cardWidth = _cardMaxWidth.toDouble();
                        }

                        if (cards.length <= divided) {
                          columns = cards.length;
                          leftFill = 0;
                        } else {
                          columns = divided;
                          leftFill =
                              (columns - (cards.length / columns).toInt());
                        }
                      }
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
  }
}
