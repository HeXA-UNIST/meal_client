import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:meal_client/l10n/app_localizations.dart';
import '../app_settings.dart';

class AllergySettingsPage extends StatelessWidget {
  const AllergySettingsPage({super.key});

  // 식품의약품안전처 알레르겐 1~19번 목록
  static const _allergenNames = {
    1:  '난류(계란)',
    2:  '우유',
    3:  '메밀',
    4:  '땅콩',
    5:  '대두(콩)',
    6:  '밀',
    7:  '고등어',
    8:  '게',
    9:  '새우',
    10: '돼지고기',
    11: '복숭아',
    12: '토마토',
    13: '아황산류',
    14: '호두',
    15: '닭고기',
    16: '쇠고기',
    17: '오징어',
    18: '어패류(굴, 전복, 홍합)',
    19: '잣',
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final enabledIds = context.watch<AppSettings>().allergy.enabledIds;

    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        title: Text(
          l10n.manageAllergies,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView.builder(
        itemCount: _allergenNames.length,
        itemBuilder: (context, index) {
          final id = index + 1;
          return CheckboxListTile(
            title: Text('$id. ${_allergenNames[id]!}'),
            value: enabledIds.contains(id),
            onChanged: (_) =>
                context.read<AppSettings>().toggleAllergen(id),
          );
        },
      ),
    );
  }
}
