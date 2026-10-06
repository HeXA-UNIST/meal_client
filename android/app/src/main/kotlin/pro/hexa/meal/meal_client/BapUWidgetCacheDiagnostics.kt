package pro.hexa.meal.meal_client

internal fun reportWidgetCacheFailure(error: Throwable) {
    runCatching {
        // JSON 예외 메시지에 포함될 수 있는 원문 대신 유형과 호출 위치만 보낸다.
        val detail = if (error is WidgetInfoCacheException) error.message else error.javaClass.simpleName
        val report = IllegalStateException("Widget cache failure: $detail")
        report.stackTrace = error.stackTrace
        reportNativeNonFatal(report)
    }
}
