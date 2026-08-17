/// 저장된 enum 이름 중 유효한 값만 집합으로 변환한다.
Set<T> enumSetFromNames<T extends Enum>(
  Iterable<String> names,
  Iterable<T> values,
) {
  final valuesByName = values.asNameMap();
  return {for (final name in names) ?valuesByName[name]};
}
