import 'package:meal_client/core/widget_shared_storage.dart';

typedef MealNotificationMutationSection =
    Future<void> Function(Future<void> Function() action);

const _mealNotificationLockFile = 'meal-notification-pending';

/// atomic exclusive-create marker로 foreground/background isolate를 직렬화한다.
Future<T> withMealNotificationMutationLock<T>(Future<T> Function() action) =>
    withSharedWidgetFileLock(_mealNotificationLockFile, action);
