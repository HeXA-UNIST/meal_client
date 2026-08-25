class AllergySettings {
  final Set<int> enabledIds;

  AllergySettings({Set<int> enabledIds = const {}})
    : enabledIds = Set.unmodifiable(enabledIds);

  AllergySettings toggle(int id) {
    final next = Set<int>.of(enabledIds);
    next.contains(id) ? next.remove(id) : next.add(id);
    return AllergySettings(enabledIds: next);
  }

  AllergySettings reset() => AllergySettings();
}
