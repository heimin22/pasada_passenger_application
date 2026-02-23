import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:pasada_passenger_app/utils/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException: $message (Status: $statusCode)';
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  final String baseUrl;

  factory ApiService() {
    return _instance;
  }

  ApiService._internal()
      : baseUrl =
            _resolveBaseUrl(dotenv.env['BACKEND_URL'], dotenv.env['API_URL']) {
    AppLogger.info('API URL configured as: $baseUrl', tag: 'ApiService');
    if (baseUrl.isEmpty) {
      AppLogger.warn('API_URL is empty in .env file', tag: 'ApiService');
    }
  }

  static String _resolveBaseUrl(String? backendUrl, String? apiUrl) {
    final backend = backendUrl?.trim();
    if (backend != null && backend.isNotEmpty) {
      return backend;
    }
    return apiUrl ?? '';
  }

  final supabase = Supabase.instance.client;

  Future<Map<String, String>> _getHeaders() async {
    final token = supabase.auth.currentSession?.accessToken;

    if (token == null) {
      throw ApiException('No access token found');
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<T?> get<T>(String endpoint, {Map<String, String>? queryParams}) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse('$baseUrl/api/$endpoint').replace(
        queryParameters: queryParams,
      );

      AppLogger.debug('GET $uri', tag: 'ApiService');
      final response = await http.get(uri, headers: headers);

      return _handleResponse<T>(response);
    } catch (e) {
      AppLogger.error('GET failed: $e', tag: 'ApiService');
      rethrow; // Rethrow to allow proper error handling upstream
    }
  }

  Future<T?> post<T>(String endpoint,
      {Map<String, dynamic>? body, Map<String, String>? queryParams}) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse('$baseUrl/api/$endpoint').replace(
        queryParameters: queryParams,
      );

      AppLogger.debug('POST $uri body: $body', tag: 'ApiService');
      final response = await http.post(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );

      return _handleResponse<T>(response);
    } catch (e) {
      AppLogger.error('POST failed: $e', tag: 'ApiService');
      rethrow; // Rethrow to allow proper error handling upstream
    }
  }

  Future<T?> put<T>(String endpoint,
      {Map<String, dynamic>? body, Map<String, String>? queryParams}) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse('$baseUrl/api/$endpoint').replace(
        queryParameters: queryParams,
      );

      AppLogger.debug('PUT $uri body: $body', tag: 'ApiService');
      final response = await http.put(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );

      return _handleResponse<T>(response);
    } catch (e) {
      AppLogger.error('PUT failed: $e', tag: 'ApiService');
      rethrow; // Rethrow to allow proper error handling upstream
    }
  }

  T? _handleResponse<T>(http.Response response) {
    final statusCode = response.statusCode;
    final responseBody = response.body;

    AppLogger.debug('Response $statusCode', tag: 'ApiService');
    if (AppLogger.verbose && responseBody.isNotEmpty) {
      _debugPrintResponseStructure(responseBody);
    }

    if (statusCode >= 200 && statusCode < 300) {
      if (responseBody.isEmpty) return null;

      try {
        final jsonResponse = jsonDecode(responseBody);
        return jsonResponse as T;
      } catch (e) {
        AppLogger.warn('Error parsing response: $e', tag: 'ApiService');
        throw ApiException('Invalid response format', statusCode: statusCode);
      }
    } else {
      String errorMessage;
      try {
        final errorJson = jsonDecode(responseBody);
        errorMessage =
            errorJson['message'] ?? errorJson['error'] ?? 'Unknown error';
      } catch (_) {
        errorMessage = responseBody;
      }

      throw ApiException(errorMessage, statusCode: statusCode);
    }
  }

  // Helper to print the full response structure for debugging
  void _debugPrintResponseStructure(String responseBody) {
    try {
      if (responseBody.isEmpty) {
        AppLogger.debug('API DEBUG: Empty response body', tag: 'ApiService');
        return;
      }

      final data = jsonDecode(responseBody);
      AppLogger.debug('API DEBUG: Response structure:', tag: 'ApiService');

      if (data is Map) {
        data.forEach((key, value) {
          AppLogger.debug('  $key: ${_formatValue(value)}', tag: 'ApiService');

          if (value is Map) {
            value.forEach((subKey, subValue) {
              AppLogger.debug('    $subKey: ${_formatValue(subValue)}',
                  tag: 'ApiService');
            });
          } else if (value is List && value.isNotEmpty) {
            AppLogger.debug('    [List with ${value.length} items]',
                tag: 'ApiService');
            if (value.first is Map) {
              final firstItem = value.first as Map;
              AppLogger.debug('    First item keys: ${firstItem.keys.toList()}',
                  tag: 'ApiService');
              firstItem.forEach((itemKey, itemValue) {
                AppLogger.debug('      $itemKey: ${_formatValue(itemValue)}',
                    tag: 'ApiService');
              });
            } else {
              AppLogger.debug('    First item: ${_formatValue(value.first)}',
                  tag: 'ApiService');
            }
          }
        });
      } else if (data is List) {
        AppLogger.debug('  [List with ${data.length} items]',
            tag: 'ApiService');
        if (data.isNotEmpty) {
          if (data.first is Map) {
            final firstItem = data.first as Map;
            AppLogger.debug('  First item keys: ${firstItem.keys.toList()}',
                tag: 'ApiService');
          } else {
            AppLogger.debug('  First item: ${data.first}', tag: 'ApiService');
          }
        }
      } else {
        AppLogger.debug('  Raw data: $data', tag: 'ApiService');
      }
    } catch (e) {
      AppLogger.warn('API DEBUG: Error parsing response JSON: $e',
          tag: 'ApiService');
    }
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return '"$value"';
    if (value is Map) return '{Map with ${value.length} entries}';
    if (value is List) return '[List with ${value.length} items]';
    return value.toString();
  }
}
