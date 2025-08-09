import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../model.dart';
import '../string.dart' as string;

class _HomePageDrawer extends StatelessWidget {
  const _HomePageDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      shape: Border(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BapUModel>(
      builder: (context, bapu, child) {
        return Scaffold(
          drawer: const _HomePageDrawer(),
          appBar: AppBar(
            title: Text(
              string.getLocalizedDate(bapu.month, bapu.day, bapu.language),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          body: child,
        );
      },
    );
  }
}
