import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class DailyForecast {
  final DateTime date;
  final double maxTempC;
  final double minTempC;
  final String condition;
  final String iconUrl;
  final int chanceOfRain;

  DailyForecast({
    required this.date,
    required this.maxTempC,
    required this.minTempC,
    required this.condition,
    required this.iconUrl,
    required this.chanceOfRain,
  });

  factory DailyForecast.fromJson(Map<String, dynamic> json) {
    final date = DateTime.parse(json['date']);
    final day = json['day'];
    final condition = day['condition'];

    return DailyForecast(
      date: date,
      maxTempC: (day['maxtemp_c'] as num).toDouble(),
      minTempC: (day['mintemp_c'] as num).toDouble(),
      condition: condition['text'],
      iconUrl: 'https:${condition['icon']}',
      chanceOfRain: (day['daily_chance_of_rain'] as num).toInt(),
    );
  }
}

class Weather {
  final String condition;
  final String iconUrl;
  final double precipitation;
  final double tempC;
  final List<DailyForecast> forecast;

  Weather({
    required this.condition,
    required this.iconUrl,
    required this.precipitation,
    required this.tempC,
    this.forecast = const [],
  });

  bool get isRaining =>
      condition.toLowerCase().contains('rain') ||
      condition.toLowerCase().contains('drizzle') ||
      condition.toLowerCase().contains('storm');

  factory Weather.fromJson(Map<String, dynamic> json) {
    final current = json['current'] as Map<String, dynamic>;
    final condition = current['condition']['text'] as String;
    final icon = current['condition']['icon'] as String;
    final precipitation = (current['precip_mm'] as num).toDouble();
    final tempC = (current['temp_c'] as num).toDouble();

    List<DailyForecast> forecastList = [];
    if (json['forecast'] != null && json['forecast']['forecastday'] != null) {
      final forecastDays = json['forecast']['forecastday'] as List;
      forecastList =
          forecastDays.map((d) => DailyForecast.fromJson(d)).toList();
    }

    return Weather(
      condition: condition,
      iconUrl: 'https:$icon',
      precipitation: precipitation,
      tempC: tempC,
      forecast: forecastList,
    );
  }
}

class WeatherService {
  final String _apiKey = dotenv.env['WEATHERAPI'] ?? '';
  static const Duration _timeout = Duration(seconds: 10);
  static const int _maxRetries = 3;
  static const Duration _baseDelay = Duration(milliseconds: 500);

  /// Fetches weather data with timeout, retry logic, and connection checking
  Future<Weather> fetchWeather(double lat, double lon) async {
    // Check internet connectivity first
    final connectivity = Connectivity();
    final connectivityResult = await connectivity.checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      throw Exception('No internet connection available');
    }

    return _fetchWeatherWithRetry(lat, lon, 0);
  }

  Future<Weather> _fetchWeatherWithRetry(
      double lat, double lon, int attempt) async {
    try {
      // Use forecast.json with days=3 to get 3-day forecast
      final url = Uri.parse(
        'https://api.weatherapi.com/v1/forecast.json?key=$_apiKey&q=$lat,$lon&days=3&aqi=no&alerts=no',
      );

      final response = await http.get(url).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return Weather.fromJson(data);
      } else if (response.statusCode >= 500 && attempt < _maxRetries) {
        // Server error - retry with exponential backoff
        final delay = _baseDelay * (1 << attempt); // Exponential backoff
        await Future.delayed(delay);
        return _fetchWeatherWithRetry(lat, lon, attempt + 1);
      } else {
        throw Exception(
            'Failed to load weather: ${response.statusCode} ${response.body}');
      }
    } on SocketException {
      if (attempt < _maxRetries) {
        final delay = _baseDelay * (1 << attempt);
        await Future.delayed(delay);
        return _fetchWeatherWithRetry(lat, lon, attempt + 1);
      }
      throw Exception('Network connection failed');
    } on HttpException {
      if (attempt < _maxRetries) {
        final delay = _baseDelay * (1 << attempt);
        await Future.delayed(delay);
        return _fetchWeatherWithRetry(lat, lon, attempt + 1);
      }
      throw Exception('HTTP request failed');
    } catch (e) {
      if (e.toString().contains('timeout') && attempt < _maxRetries) {
        final delay = _baseDelay * (1 << attempt);
        await Future.delayed(delay);
        return _fetchWeatherWithRetry(lat, lon, attempt + 1);
      }
      rethrow;
    }
  }
}
