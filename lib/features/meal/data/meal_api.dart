import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/network/http_client.dart';

Future<String> fetchRawMeal() => fetchRawString(ApiConstants.mealEndpoint);
