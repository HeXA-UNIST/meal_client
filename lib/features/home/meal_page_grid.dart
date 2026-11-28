import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/l10n/app_localizations.dart';

import 'meal_card.dart';

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

class MealPageGrid extends StatelessWidget {
  const MealPageGrid({
    super.key,
    required this.meal,
    required this.mealOfDay,
    required this.targetDate,
    required this.appInfo,
    required this.currentKstDateTime,
  });

  final CafeteriaMeal meal;
  final MealOfDay mealOfDay;
  final DateTime targetDate;
  final Future<AppInfo> appInfo;
  final DateTime? currentKstDateTime;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 좁은 화면에서는 이 여백 2dp와 카드 위쪽 여백 8dp를 더해
    // 끼니 버튼과 요일 탭 사이의 간격(10dp)에 맞춘다. 이 여백도 본문과 함께 스크롤된다.
    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.sizeOf(context).width < 840 ? 2 : 10,
      ),
      child: FutureBuilder<AppInfo>(
        future: appInfo,
        builder: (context, infoSnapshot) {
          return SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cardCount = Cafeteria.values.fold<int>(
                  0,
                  (count, cafeteria) =>
                      count + meal.fromCafeteria(cafeteria).length,
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
                  var divided = (constraints.maxWidth / _cardMaxWidth).toInt();
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
                      final meals = meal.fromCafeteria(cafeteria);
                      return meals.map((meal) {
                        final columnIndex = cardIndex % columns;
                        final rowIndex = cardIndex ~/ columns;
                        cardIndex++;
                        var title = switch (cafeteria) {
                          Cafeteria.dormitory => l10n.dormitoryCafeteria,
                          Cafeteria.student => l10n.studentCafeteria,
                          Cafeteria.faculty => l10n.facultyCafeteria,
                        };

                        // 기숙사 식당 카드에만 한식·할랄 구분을 표시한다.
                        if (cafeteria == Cafeteria.dormitory) {
                          final mealType = switch (meal) {
                            KoreanMeal _ => l10n.menuKorean,
                            HalalMeal _ => l10n.menuHalal,
                            _ => null,
                          };
                          if (mealType != null) {
                            title = l10n.cafeteriaWithMealType(title, mealType);
                          }
                        }

                        final operatingTime = infoSnapshot.data?.operatingHours
                            .forDate(targetDate)
                            .timeFor(cafeteria, mealOfDay);
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
                          // 바깥 여백은 8dp다. 이웃한 카드에는 각각 6dp의 여백을 두어
                          // 가로와 세로 모두 카드 사이가 12dp가 되도록 한다.
                          margin: EdgeInsets.fromLTRB(
                            columnIndex == 0
                                ? _cardOuterMargin
                                : _cardInnerMargin,
                            rowIndex == 0 ? _cardOuterMargin : _cardInnerMargin,
                            columnIndex == columns - 1
                                ? _cardOuterMargin
                                : _cardInnerMargin,
                            rowIndex == rowCount - 1
                                ? _cardOuterMargin
                                : _cardInnerMargin,
                          ),
                          operatingTimeLabel: operatingTime?.label,
                          isOperating: isOperating,
                          // 웹에서는 길게 눌러 공유하는 기능을 끈다. 마우스를 올리면
                          // 복사 버튼을 표시하는 방식은 후속 개선으로 남겨 둔다.
                          onLongPress: kIsWeb
                              ? null
                              : (sharePositionOrigin) {
                                  final languageCode = Localizations.localeOf(
                                    context,
                                  ).languageCode;
                                  SharePlus.instance.share(
                                    ShareParams(
                                      sharePositionOrigin: sharePositionOrigin,
                                      text: buildMealShareText(
                                        cardTitle: title,
                                        targetDate: targetDate,
                                        mealOfDayLabel: switch (mealOfDay) {
                                          MealOfDay.breakfast => l10n.breakfast,
                                          MealOfDay.lunch => l10n.lunch,
                                          MealOfDay.dinner => l10n.dinner,
                                        },
                                        meal: meal,
                                        languageCode: languageCode,
                                        convenienceLabel:
                                            l10n.menuSectionConvenience,
                                        specialLabel: l10n.menuSectionSpecial,
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

                // 카드 너비가 같으므로 운영시간과 칼로리가 모두 있는 경우를 기준으로
                // 배율을 한 번 계산한다. 일부 항목이 빠진 카드에도 같은 배율을 적용해
                // 글자와 아이콘 크기를 일정하게 유지한다.
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
      ),
    );
  }
}
