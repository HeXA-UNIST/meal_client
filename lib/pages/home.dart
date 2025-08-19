import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../model.dart';
import '../meal.dart';
import '../data.dart';
import '../i18n.dart';
import '../api_v2.dart';
import '../string.dart' as string;

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _DrawerItem({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      contentPadding: EdgeInsets.only(left: 40),
      onTap: onTap,
    );
  }
}

class _Announcement extends StatelessWidget {
  final String close;
  final String title;
  final String content;

  const _Announcement({
    super.key,
    required this.close,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/imgs/bapu_logo.svg',
            height: 24,
            colorFilter: ColorFilter.mode(
              theme.colorScheme.primaryContainer,
              BlendMode.srcIn,
            ),
          ),
          SizedBox(height: 10),
          Text(title),
        ],
      ),
      content: SingleChildScrollView(
        child: ListBody(children: [Text(content)]),
      ),
      actions: [
        TextButton(
          child: Text(close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _HomePageDrawer extends StatelessWidget {
  const _HomePageDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final language = Provider.of<BapUModel>(context).language;

    return Drawer(
      backgroundColor: brightness == Brightness.light
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainer,

      child: ListView(
        padding: EdgeInsets.all(0),
        children: [
          Container(
            height: 160,
            alignment: Alignment.bottomLeft,
            margin: EdgeInsets.only(bottom: 50, left: 40),
            child: SvgPicture.asset('assets/imgs/bapu_logo.svg', height: 36),
          ),
          _DrawerItem(
            icon: Icons.notifications_active,
            title: string.announcement.getLocalizedString(language),
            onTap: () async {
              Navigator.of(context).pop();
              final sharedPreferences = await SharedPreferences.getInstance();
              final announcement = sharedPreferences.getString("announceTime");
              if (announcement != null && context.mounted) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext context) {
                    return _Announcement(
                      close: string.close.getLocalizedString(language),
                      title: string.announcement.getLocalizedString(language),
                      content: announcement,
                    );
                  },
                );
              }
            },
          ),
          _DrawerItem(
            icon: Icons.info,
            title: string.operationhours.getLocalizedString(language),
            onTap: () {
              Navigator.of(context).pop();
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (BuildContext context) {
                  return _Announcement(
                    close: string.close.getLocalizedString(language),
                    title: string.operationhours.getLocalizedString(language),
                    content: string.operationhourscontent.getLocalizedString(
                      language,
                    ),
                  );
                },
              );
            },
          ),
          _DrawerItem(
            icon: Icons.help_outline_outlined,
            title: string.contactdeveloper.getLocalizedString(language),
            onTap: () async =>
                await launchUrl(Uri.parse("https://pf.kakao.com/_xcaYlxj")),
          ),
          /*
          _DrawerItem(
            icon: Icons.language,
            title: string.language.getLocalizedString(language),
            onTap: () {},
          ),
          */
          _DrawerItem(
            icon: Icons.copyright,
            title: string.ossLicense.getLocalizedString(language),
            onTap: () => showLicensePage(context: context),
          ),
        ],
      ),
    );
  }
}

class _MealOfDaySwitchButton extends StatelessWidget {
  const _MealOfDaySwitchButton({
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

class _DayOfWeekTabBar extends StatelessWidget implements PreferredSizeWidget {
  _DayOfWeekTabBar({
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
          labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          labelPadding: EdgeInsets.zero,
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => Colors.transparent,
          ),
          splashFactory: NoSplash.splashFactory,
          dividerHeight: 0,
          controller: tabController,
        ),
      ),
    );
  }
}

enum _CurrentlyScrolling { inner, outer }

class _NestedVerticalPageTabBarView extends StatefulWidget {
  const _NestedVerticalPageTabBarView({
    super.key,
    required this.pageController,
    required this.tabController,
    required this.tabCount,
    required this.pageCount,
    required this.onPageChanged,
    required this.builder,
  });

  final PageController pageController;
  final TabController tabController;
  final int tabCount;
  final int pageCount;
  final void Function(int page) onPageChanged;
  final Widget Function(BuildContext context, int tabIndex, int pageIndex)
  builder;

  @override
  State<_NestedVerticalPageTabBarView> createState() =>
      _NestedVerticalPageTabBarViewState();
}

class _NestedVerticalPageTabBarViewState
    extends State<_NestedVerticalPageTabBarView> {
  late final List<List<ScrollController>> scrollControllers;
  Drag? drag;
  int? currentPageIndex;
  late List<bool> pageReverseList;
  double prevPage = 0;
  _CurrentlyScrolling? currentlyScrolling;

  @override
  void initState() {
    scrollControllers = List.generate(
      widget.tabCount,
      (tabIndex) => List.generate(
        widget.pageCount,
        (pageIndex) => ScrollController(),
        growable: false,
      ),
      growable: false,
    );
    pageReverseList = List.generate(
      widget.pageCount,
      (_) => false,
      growable: false,
    );
    widget.tabController.addListener(
      () => setState(() {
        pageReverseList.fillRange(0, pageReverseList.length, false);
      }),
    );
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragStart: (details) {
        final mediaQuery = MediaQuery.of(context);
        if (details.globalPosition.dy >=
            mediaQuery.size.height - mediaQuery.padding.bottom) {
          return;
        }

        currentPageIndex = widget.pageController.page!.round();

        final scrollController =
            scrollControllers[widget.tabController.index][currentPageIndex!];
        final ScrollController currentController;
        if (scrollController.position.atEdge) {
          currentlyScrolling = _CurrentlyScrolling.outer;
          currentController = widget.pageController;

          setState(() {
            pageReverseList.fillRange(0, currentPageIndex!, true);
            if (currentPageIndex! < widget.pageCount - 1) {
              pageReverseList.fillRange(
                currentPageIndex! + 1,
                widget.pageCount - 1,
                false,
              );
            }
            for (var c in scrollControllers[widget.tabController.index]) {
              if (c != scrollController && c.hasClients) {
                c.jumpTo(0);
              }
            }
          });
        } else {
          currentlyScrolling = _CurrentlyScrolling.inner;
          currentController = scrollController;
        }

        drag = currentController.position.drag(details, () {});
        prevPage = widget.pageController.page!;
      },
      onVerticalDragUpdate: (details) {
        if (drag == null) {
          return;
        }

        final scrollController =
            scrollControllers[widget.tabController.index][currentPageIndex!];

        final double startScrollExtent;
        final double endScrollExtent;
        if (pageReverseList[currentPageIndex!]) {
          startScrollExtent = scrollController.position.maxScrollExtent;
          endScrollExtent = scrollController.position.minScrollExtent;
        } else {
          startScrollExtent = scrollController.position.minScrollExtent;
          endScrollExtent = scrollController.position.maxScrollExtent;
        }

        final currentPage = widget.pageController.page!;
        final middlePage = ((currentPage + prevPage) / 2).round();

        if (currentlyScrolling == _CurrentlyScrolling.outer &&
            startScrollExtent != endScrollExtent &&
            ((scrollController.position.pixels == startScrollExtent &&
                    details.delta.direction < 0) ||
                (scrollController.position.pixels == endScrollExtent &&
                    details.delta.direction > 0)) &&
            ((prevPage <= middlePage && middlePage <= currentPage) ||
                (currentPage <= middlePage && middlePage <= prevPage))) {
          drag?.cancel();

          currentlyScrolling = _CurrentlyScrolling.inner;
          drag = scrollController.position.drag(
            DragStartDetails(
              globalPosition: details.globalPosition,
              localPosition: details.localPosition,
            ),
            () {},
          );
        }

        drag?.update(details);
        prevPage = currentPage;
      },
      onVerticalDragEnd: (details) {
        drag?.end(details);
        drag = null;
        currentPageIndex = null;
        currentlyScrolling = null;
      },
      child: PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: widget.pageCount,
        controller: widget.pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: widget.onPageChanged,
        hitTestBehavior: HitTestBehavior.deferToChild,
        itemBuilder: (BuildContext context, int pageIndex) {
          return TabBarView(
            controller: widget.tabController,
            children: List.generate(widget.tabCount, (tabIndex) {
              final bool reverse;
              if (tabIndex == widget.tabController.index &&
                  pageReverseList[pageIndex]) {
                reverse = true;
              } else {
                reverse = false;
              }

              return LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  controller: scrollControllers[tabIndex][pageIndex],
                  reverse: reverse,
                  physics: const NeverScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: widget.builder(context, tabIndex, pageIndex),
                    ),
                  ),
                ),
              );
            }, growable: false),
          );
        },
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({super.key, required this.title, required this.meal});

  final String title;
  final Meal meal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card.filled(
      color: theme.colorScheme.surfaceContainer,
      margin: EdgeInsetsGeometry.all(8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadiusGeometry.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: Flex(
        direction: Axis.vertical,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ColoredBox(
            color: HSLColor.fromColor(theme.colorScheme.primaryContainer)
                .withSaturation(0.5)
                .withLightness(
                  theme.brightness == Brightness.light ? 0.94 : 0.06,
                )
                .toColor(),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Center(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall!.copyWith(
                    color:
                        HSLColor.fromColor(theme.colorScheme.primaryContainer)
                            .withSaturation(0.8)
                            .withLightness(
                              theme.brightness == Brightness.light ? 0.3 : 0.7,
                            )
                            .toColor(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...meal.menu.map(
            (aMenu) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(aMenu),
            ),
          ),
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
                        style: theme.textTheme.labelMedium,
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

const _cardMinWidth = 160;
const _cardMaxWidth = 196;

class _WeekMealTabBarView extends StatelessWidget {
  const _WeekMealTabBarView({
    super.key,
    required this.weekMeal,
    required this.tabController,
    required this.pageController,
    required this.pageCount,
    required this.onPageChanged,
    required this.language,
  });

  final WeekMeal weekMeal;
  final TabController tabController;
  final PageController pageController;
  final int pageCount;
  final void Function(int) onPageChanged;
  final Language language;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: pageController,
      child: _NestedVerticalPageTabBarView(
        pageController: pageController,
        tabController: tabController,
        pageCount: pageCount,
        tabCount: DayOfWeek.values.length,
        onPageChanged: onPageChanged,
        builder: (context, tabIndex, pageIndex) {
          final nowMeal = weekMeal
              .fromDayOfWeek(DayOfWeek.values[tabIndex])
              .fromMealOfDay(MealOfDay.values[pageIndex]);
          return SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cards = <Widget>[
                  ...nowMeal.dormitory.map(
                    (meal) => _MealCard(
                      title:
                          string.dormitoryCafeteria.getLocalizedString(
                            language,
                          ) +
                          (meal is KoreanMeal
                              ? " ${string.menuKorean.getLocalizedString(language)}"
                              : (meal is HalalMeal
                                    ? " ${string.menuHalal.getLocalizedString(language)}"
                                    : "")),
                      meal: meal,
                    ),
                  ),
                  ...nowMeal.student.map(
                    (meal) => _MealCard(
                      title: string.studentCafeteria.getLocalizedString(
                        language,
                      ),
                      meal: meal,
                    ),
                  ),
                  ...nowMeal.faculty.map(
                    (meal) => _MealCard(
                      title: string.diningHall.getLocalizedString(language),
                      meal: meal,
                    ),
                  ),
                ];

                final double cardWidth;
                final int columns;
                final int leftFill;
                {
                  var divided = (constraints.maxWidth / _cardMaxWidth).toInt();
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
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final HomePageModel _model;
  late final DateTime _mondayOfWeek;
  late final TabController _tabController;
  late final PageController _mealOfDayPageController;

  late final Future<WeekMeal> cachedMeal;
  late final Future<WeekMeal> downloadedMeal;

  @override
  void initState() {
    final DateTime now;
    {
      final localNow = DateTime.now();
      now = localNow.toUtc().add(Duration(hours: 9));
    }

    final MealOfDay mealOfDay;
    if (now.hour < 9 || (now.hour == 9 && now.minute <= 20)) {
      mealOfDay = MealOfDay.breakfast;
    } else if (now.hour < 13 || (now.hour == 13 && now.minute <= 30)) {
      mealOfDay = MealOfDay.lunch;
    } else {
      mealOfDay = MealOfDay.dinner;
    }

    _model = HomePageModel(
      mealOfDay: mealOfDay,
      dayOfWeek: DayOfWeek.values[now.weekday - 1],
    );

    _mondayOfWeek = now.subtract(Duration(days: now.weekday - 1));

    _tabController = TabController(
      length: DayOfWeek.values.length,
      vsync: this,
    );
    _tabController.index = _model.dayOfWeek.index;
    _tabController.addListener(
      () => setState(() {
        _model.dayOfWeek = DayOfWeek.values[_tabController.index];
      }),
    );

    _mealOfDayPageController = PageController(
      initialPage: _model.mealOfDay.index,
    );

    cachedMeal = getCachedMealData();
    downloadedMeal = cachedMeal.then(
      (cache) => fetchAndCacheMealData(),
      onError: (e) => fetchAndCacheMealData(),
    );

    fetchRawAnnouncement().then((rawAnnouncement) async {
      const key = "announceTime";
      try {
        final announcement = parseRawAnnouncement(rawAnnouncement);
        final sharedPreferences = await SharedPreferences.getInstance();
        final prevAnnouncement = sharedPreferences.getString(key);
        if (announcement != prevAnnouncement) {
          sharedPreferences.setString(key, announcement);
          SchedulerBinding.instance.addPostFrameCallback((duration) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) {
                return Consumer<BapUModel>(
                  builder: (context, bapu, child) => _Announcement(
                    close: string.close.getLocalizedString(bapu.language),
                    title: string.announcement.getLocalizedString(
                      bapu.language,
                    ),
                    content: announcement,
                  ),
                );
              },
            );
          });
        }
      } catch (_) {
        // ignore
      }
    });

    rootBundle
        .loadString("assets/fonts/Pretendard-License.txt")
        .then(
          (fontLicense) => LicenseRegistry.addLicense(
            () => Stream<LicenseEntry>.value(
              LicenseEntryWithLineBreaks(["Pretendard"], fontLicense),
            ),
          ),
        );

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BapUModel>(
      builder: (context, bapu, child) {
        final String dayOfMealLabel;
        final IconData dayOfMealIcon;
        switch (_model.mealOfDay) {
          case MealOfDay.breakfast:
            dayOfMealLabel = string.breakfast.getLocalizedString(bapu.language);
            dayOfMealIcon = Icons.sunny;
          case MealOfDay.lunch:
            dayOfMealLabel = string.lunch.getLocalizedString(bapu.language);
            dayOfMealIcon = Icons.restaurant;
          case MealOfDay.dinner:
            dayOfMealLabel = string.dinner.getLocalizedString(bapu.language);
            dayOfMealIcon = Icons.nightlight;
        }

        final theDay = _mondayOfWeek.add(
          Duration(days: _model.dayOfWeek.index),
        );

        final dayOfWeekTabBar = _DayOfWeekTabBar(
          tabController: _tabController,
          language: bapu.language,
        );
        final PreferredSizeWidget? bottom;
        final Widget? flexibleSpace;
        if (MediaQuery.of(context).size.width >= 840) {
          flexibleSpace = SafeArea(
            child: Center(child: SizedBox(width: 420, child: dayOfWeekTabBar)),
          );
          bottom = null;
        } else {
          bottom = dayOfWeekTabBar;
          flexibleSpace = null;
        }

        final colorScheme = Theme.of(context).colorScheme;

        return Scaffold(
          drawer: const _HomePageDrawer(),
          appBar: AppBar(
            titleSpacing: 0,
            centerTitle: false,
            title: Text(
              string.getLocalizedDate(theDay.month, theDay.day, bapu.language),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            actions: [
              _MealOfDaySwitchButton(
                onPressed: () => setState(() {
                  _model.mealOfDay = nextMealOfDay(_model.mealOfDay);
                  try {
                    _mealOfDayPageController.animateToPage(
                      _model.mealOfDay.index,
                      duration: Duration(milliseconds: 300),
                      curve: Curves.ease,
                    );
                  } catch (e) {
                    // ignore
                  }
                }),
                label: dayOfMealLabel,
                icon: dayOfMealIcon,
              ),
            ],
            actionsPadding: EdgeInsets.only(right: 8),
            backgroundColor: colorScheme.surface,
            scrolledUnderElevation: 0,
            bottom: bottom,
            flexibleSpace: flexibleSpace,
          ),
          body: child,
        );
      },
      child: FutureBuilder(
        future: cachedMeal,
        builder: (context, cacheSnapshot) {
          final theme = Theme.of(context);

          if (cacheSnapshot.hasData || cacheSnapshot.hasError) {
            return FutureBuilder(
              future: downloadedMeal,
              builder: (context, downloadSnapshot) {
                if (downloadSnapshot.hasData || cacheSnapshot.hasData) {
                  return Consumer<BapUModel>(
                    builder: (context, bapu, child) => _WeekMealTabBarView(
                      pageCount: MealOfDay.values.length,
                      weekMeal: downloadSnapshot.hasData
                          ? downloadSnapshot.data!
                          : cacheSnapshot.data!,
                      tabController: _tabController,
                      pageController: _mealOfDayPageController,
                      onPageChanged: (page) => setState(
                        () => _model.mealOfDay = MealOfDay.values[page],
                      ),
                      language: bapu.language,
                    ),
                  );
                } else if (!cacheSnapshot.hasError ||
                    !downloadSnapshot.hasError) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: theme.colorScheme.primaryContainer,
                    ),
                  );
                } else {
                  return Center(
                    child: Consumer<BapUModel>(
                      builder: (context, bapu, child) => Text(
                        string.cannotLoadMeal.getLocalizedString(bapu.language),
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  );
                }
              },
            );
          } else {
            return Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
            );
          }
        },
      ),
    );
  }
}
