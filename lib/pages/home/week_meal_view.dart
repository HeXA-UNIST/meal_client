import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../i18n.dart';
import '../../meal.dart';
import '../../string.dart' as string;
import 'meal_card.dart';
import 'nested_page_scroll.dart';

const _cardMinWidth = 160;
const _cardMaxWidth = 196;

class WeekMealTabBarView extends StatelessWidget {
  const WeekMealTabBarView({
    super.key,
    required this.weekMeal,
    required this.tabController,
    required this.pageControllerGroup,
    required this.pageCount,
    required this.onPageChanged,
    required this.language,
  });

  final WeekMeal weekMeal;
  final TabController tabController;
  final NestedPageScrollControllerGroup pageControllerGroup;
  final int pageCount;
  final void Function(int) onPageChanged;
  final Language language;

  @override
  Widget build(BuildContext context) {
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
            return SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cards = Cafeteria.values
                      .map<Iterable<Widget>>(
                        (cafeteria) {
                          final meals = nowMeal.fromCafeteria(cafeteria);
                          return meals.map((meal) {
                            var title = switch (cafeteria) {
                              Cafeteria.dormitory => string.dormitoryCafeteria.getLocalizedString(language),
                              Cafeteria.student   => string.studentCafeteria.getLocalizedString(language),
                              Cafeteria.faculty   => string.facultyCafeteria.getLocalizedString(language),
                            };

                            // 한식, 할랄 표기는 기숙사 식당에 한정하여 표기한다.
                            if (cafeteria == Cafeteria.dormitory) {
                              switch (meal) {
                                case KoreanMeal _:
                                  title +=
                                  " ${string.menuKorean.getLocalizedString(language)}";
                                case HalalMeal _:
                                  title +=
                                  " ${string.menuHalal.getLocalizedString(language)}";
                              }
                            }

                            return GestureDetector(
                              onLongPress: () {
                                HapticFeedback.lightImpact();
                                SharePlus.instance.share(
                                  ShareParams(
                                    text:
                                        "[$title]\n${meal.menu.map((aMenu) => "- $aMenu").join("\n")}${meal.kcal == null ? "" : "\n\n${meal.kcal} kcal"}",
                                  ),
                                );
                              },
                              child: MealCard(title: title, meal: meal),
                            );
                          });
                        },
                      )
                      .expand((e) => e)
                      .toList(growable: true);

                  if (cards.isEmpty) {
                    return Center(
                      child: Text(
                        string.noMeal.getLocalizedString(language),
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
                      leftFill = (columns - (cards.length / columns).toInt());
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
                          TableCell(child: SizedBox()),
                          ...cards
                              .sublist(
                                i * columns,
                                end < cards.length ? end : cards.length,
                              )
                              .map((card) => TableCell(child: card)),
                          TableCell(child: SizedBox()),
                        ],
                      ),
                    );
                  }
                  final remain = cards
                      .sublist(columns * rows)
                      .map((card) => TableCell(child: card))
                      .toList();
                  if (remain.isNotEmpty) {
                    remain.insert(0, TableCell(child: SizedBox()));
                    remain.add(TableCell(child: SizedBox()));
                    row.add(TableRow(children: remain));
                  }

                  return Table(
                    border: const TableBorder(),
                    defaultColumnWidth: FixedColumnWidth(cardWidth),
                    columnWidths: {
                      0: FlexColumnWidth(),
                      columns + 1: FlexColumnWidth(),
                    },
                    defaultVerticalAlignment:
                        TableCellVerticalAlignment.intrinsicHeight,
                    children: row,
                  );
                },
              ),
            );
          },
        ),
        growable: false,
      ),
    );
  }
}
