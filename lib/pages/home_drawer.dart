import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n.dart';
import '../model.dart';
import '../string.dart' as string;

Future<void>? _fontLicenseRegistrationFuture;

class HomeAnnouncementDialog extends StatelessWidget {
  final String close;
  final String title;
  final String content;

  const HomeAnnouncementDialog({
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

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _DrawerItem({
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

// 운영시간은 일단 하드코딩. 추후 백엔드 API로 받아올 예정
class _OperationHoursSection extends StatelessWidget {
  final Language language;

  const _OperationHoursSection({required this.language});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            string.operationHours.getLocalizedString(language),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 16),
          _OperationHoursEntry(
            name: string.dormitoryCafeteria.getLocalizedString(language),
            hours: ['08:00 - 09:20', '11:30 - 13:30', '17:30 - 19:00'],
          ),
          SizedBox(height: 12),
          _OperationHoursEntry(
            name: string.studentCafeteria.getLocalizedString(language),
            hours: ['11:00 - 13:30', '17:00 - 19:00'],
          ),
          SizedBox(height: 12),
          _OperationHoursEntry(
            name: string.facultyCafeteria.getLocalizedString(language),
            hours: ['11:00 - 13:00', '17:30 - 19:30'],
          ),
        ],
      ),
    );
  }
}

class _OperationHoursEntry extends StatelessWidget {
  final String name;
  final List<String> hours;

  const _OperationHoursEntry({required this.name, required this.hours});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          name,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 4),
        ...hours.map(
          (h) => Text(
            h,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class HomePageDrawer extends StatelessWidget {
  const HomePageDrawer({super.key});

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
        padding: EdgeInsets.zero,
        children: [
          Container(
            height: 130,
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
                    return HomeAnnouncementDialog(
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
            icon: Icons.help_outline_outlined,
            title: string.contactDeveloper.getLocalizedString(language),
            onTap: () async =>
                await launchUrl(Uri.parse("https://pf.kakao.com/_xcaYlxj")),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            child: Divider(color: Colors.white54, height: 1),
          ),
          _OperationHoursSection(language: language),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            child: Divider(color: Colors.white54, height: 1),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(left: 28, bottom: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: Icon(Icons.copyright, color: Colors.white),
                  onPressed: () async {
                    await (_fontLicenseRegistrationFuture ??=
                        rootBundle.loadString('assets/fonts/Pretendard-License.txt').then((fontLicense) {
                          LicenseRegistry.addLicense(
                            () => Stream<LicenseEntry>.value(
                              LicenseEntryWithLineBreaks(['Pretendard'], fontLicense),
                            ),
                          );
                        }));
                    if (!context.mounted) {
                      return;
                    }
                    showLicensePage(
                      context: context,
                      applicationLegalese:
                          "GPL-2.0 license. Source code: https://github.com/HeXA-UNIST/meal_client",
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
