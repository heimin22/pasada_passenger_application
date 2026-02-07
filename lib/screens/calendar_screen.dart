import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasada_passenger_app/providers/weather_provider.dart';
import 'package:pasada_passenger_app/services/calendar_service.dart';
import 'package:pasada_passenger_app/services/location_weather_service.dart';
import 'package:pasada_passenger_app/services/weather_service.dart';
import 'package:provider/provider.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool? _isHoliday;
  String? _holidayName;
  Map<DateTime, String> _holidayByDate = {};

  // New state variables
  late Timer _timer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _checkHolidayStatus();
    _loadVisibleRangeHolidays();

    // Start timer for time display
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });

    // Initialize weather if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initWeather();
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _initWeather() async {
    final weatherProv = Provider.of<WeatherProvider>(context, listen: false);
    if (weatherProv.weather == null) {
      final initialized = await weatherProv.initializeWeatherService();
      if (!initialized) {
        await LocationWeatherService.refreshWeatherNow(weatherProv);
      }
    }
  }

  Future<void> _checkHolidayStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final isHoliday =
          await CalendarService.instance.isPhilippineHoliday(_selectedDate);
      final holidayName = isHoliday
          ? await CalendarService.instance.getHolidayName(_selectedDate)
          : null;
      if (mounted) {
        setState(() {
          _isHoliday = isHoliday;
          _holidayName = holidayName;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isHoliday = null;
          _holidayName = null;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadVisibleRangeHolidays() async {
    // Determine current visible grid range (6 weeks grid)
    final DateTime currentMonth =
        DateTime(_selectedDate.year, _selectedDate.month);
    final DateTime firstDayOfMonth = currentMonth;
    final int firstWeekday = firstDayOfMonth.weekday; // Mon=1..Sun=7

    final DateTime firstVisibleDay =
        firstDayOfMonth.subtract(Duration(days: firstWeekday - 1));
    final int totalCells = 42; // 6 weeks * 7 days
    final DateTime lastVisibleDay = firstVisibleDay.add(
      Duration(days: totalCells - 1),
    );

    final Map<DateTime, String> holidays = await CalendarService.instance
        .getHolidaysInRange(firstVisibleDay, lastVisibleDay);
    if (!mounted) return;
    setState(() {
      _holidayByDate = holidays;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor:
            isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
        foregroundColor:
            isDarkMode ? const Color(0xFFF5F5F5) : const Color(0xFF121212),
        title: const Text(
          'Calendar',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
          ),
        ),
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time Display
            _buildTimeDisplay(isDarkMode),
            const SizedBox(height: 24),

            // Weather & Commute
            _buildWeatherSection(isDarkMode),
            const SizedBox(height: 24),

            // Calendar Widget
            Container(
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF1A1A1A)
                    : const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: isDarkMode
                        ? const Color(0xFF2A2A2A)
                        : const Color(0xFFE0E0E0),
                    width: 1),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: isDarkMode
                      ? const ColorScheme.dark(
                          primary: Color(0xFF00CC58),
                          onPrimary: Color(0xFF121212),
                          surface: Color(0xFF1E1E1E),
                          onSurface: Color(0xFFF5F5F5),
                        )
                      : const ColorScheme.light(
                          primary: Color(0xFF00CC58),
                          onPrimary: Color(0xFFFFFFFF),
                          surface: Color(0xFFFFFFFF),
                          onSurface: Color(0xFF121212),
                        ),
                  textButtonTheme: TextButtonThemeData(
                    style: TextButton.styleFrom(
                      shape: const CircleBorder(),
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ),
                child: _buildCustomCalendar(isDarkMode),
              ),
            ),
            const SizedBox(height: 24),

            // Holiday Status Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF1A1A1A)
                    : const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: isDarkMode
                        ? const Color(0xFF2A2A2A)
                        : const Color(0xFFE0E0E0),
                    width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isHoliday == true ? Icons.event_busy : Icons.event,
                        color: const Color(0xFF00CC58),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _isLoading
                              ? 'Checking holiday status...'
                              : _isHoliday == true
                                  ? _holidayName == null ||
                                          _holidayName!.isEmpty
                                      ? 'Philippine Holiday'
                                      : 'Philippine Holiday — ${_holidayName!}'
                                  : 'Regular Day',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode
                                ? const Color(0xFFF5F5F5)
                                : const Color(0xFF121212),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(
                        color: Color(0xFF00CC58),
                        backgroundColor: Color(0xFF2A2A2A),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Discount Rules Explanation
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF1E1E1E)
                    : const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00CC58), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFF00CC58),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Student Discount Rules',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode
                              ? const Color(0xFFF5F5F5)
                              : const Color(0xFF121212),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'How the calendar affects your student discount:',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isDarkMode
                          ? const Color(0xFFF5F5F5)
                          : const Color(0xFF121212),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildRuleItem(
                    icon: Icons.school,
                    title: 'Regular Days',
                    description:
                        'Student discount (20%) is available on all regular school days.',
                    isActive: _isHoliday != true,
                    isDarkMode: isDarkMode,
                  ),
                  const SizedBox(height: 14),
                  _buildRuleItem(
                    icon: Icons.event_busy,
                    title: 'Philippine Holidays',
                    description:
                        'No student discount on official Philippine holidays when classes are suspended.',
                    isActive: _isHoliday == true,
                    isDarkMode: isDarkMode,
                  ),
                  const SizedBox(height: 14),
                  _buildRuleItem(
                    icon: Icons.people,
                    title: 'Other Discounts',
                    description:
                        'Senior Citizen and PWD discounts are always available regardless of holidays.',
                    isActive: false,
                    isDarkMode: isDarkMode,
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? const Color(0xFF1A1A1A)
                          : const Color(0xFFE8E8E8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Note: This calendar uses official Philippine holidays from Google Calendar. The discount rules are automatically applied when you select "Student" as your passenger type.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        color: isDarkMode
                            ? const Color(0xFFCCCCCC)
                            : const Color(0xFF666666),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomCalendar(bool isDarkMode) {
    final now = DateTime.now();
    final currentMonth = DateTime(_selectedDate.year, _selectedDate.month);
    final firstDayOfMonth = currentMonth;
    final lastDayOfMonth =
        DateTime(_selectedDate.year, _selectedDate.month + 1, 0);
    final firstWeekday = firstDayOfMonth.weekday;

    // Generate calendar days
    final List<DateTime> calendarDays = [];

    // Add days from previous month to fill the first week
    for (int i = firstWeekday - 1; i > 0; i--) {
      calendarDays.add(firstDayOfMonth.subtract(Duration(days: i)));
    }

    // Add days of current month
    for (int day = 1; day <= lastDayOfMonth.day; day++) {
      calendarDays.add(DateTime(_selectedDate.year, _selectedDate.month, day));
    }

    // Add days from next month to fill the last week
    int remainingDays = 42 - calendarDays.length; // 6 weeks * 7 days
    for (int day = 1; day <= remainingDays; day++) {
      calendarDays
          .add(DateTime(_selectedDate.year, _selectedDate.month + 1, day));
    }

    return Column(
      children: [
        // Month/Year header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedDate =
                        DateTime(_selectedDate.year, _selectedDate.month - 1);
                  });
                  _loadVisibleRangeHolidays();
                },
                icon: const Icon(Icons.chevron_left, color: Color(0xFF00CC58)),
              ),
              Text(
                '${_getMonthName(_selectedDate.month)} ${_selectedDate.year}',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode
                      ? const Color(0xFFF5F5F5)
                      : const Color(0xFF121212),
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedDate =
                        DateTime(_selectedDate.year, _selectedDate.month + 1);
                  });
                  _loadVisibleRangeHolidays();
                },
                icon: const Icon(Icons.chevron_right, color: Color(0xFF00CC58)),
              ),
            ],
          ),
        ),

        // Weekday headers
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                  child: Center(
                      child: Text('S',
                          style: TextStyle(
                              color: isDarkMode
                                  ? const Color(0xFF999999)
                                  : const Color(0xFF666666),
                              fontSize: 12)))),
              Expanded(
                  child: Center(
                      child: Text('M',
                          style: TextStyle(
                              color: isDarkMode
                                  ? const Color(0xFF999999)
                                  : const Color(0xFF666666),
                              fontSize: 12)))),
              Expanded(
                  child: Center(
                      child: Text('T',
                          style: TextStyle(
                              color: isDarkMode
                                  ? const Color(0xFF999999)
                                  : const Color(0xFF666666),
                              fontSize: 12)))),
              Expanded(
                  child: Center(
                      child: Text('W',
                          style: TextStyle(
                              color: isDarkMode
                                  ? const Color(0xFF999999)
                                  : const Color(0xFF666666),
                              fontSize: 12)))),
              Expanded(
                  child: Center(
                      child: Text('T',
                          style: TextStyle(
                              color: isDarkMode
                                  ? const Color(0xFF999999)
                                  : const Color(0xFF666666),
                              fontSize: 12)))),
              Expanded(
                  child: Center(
                      child: Text('F',
                          style: TextStyle(
                              color: isDarkMode
                                  ? const Color(0xFF999999)
                                  : const Color(0xFF666666),
                              fontSize: 12)))),
              Expanded(
                  child: Center(
                      child: Text('S',
                          style: TextStyle(
                              color: isDarkMode
                                  ? const Color(0xFF999999)
                                  : const Color(0xFF666666),
                              fontSize: 12)))),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Calendar grid
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
            ),
            itemCount: calendarDays.length,
            itemBuilder: (context, index) {
              final day = calendarDays[index];
              final isCurrentMonth = day.month == _selectedDate.month;
              final isToday = day.day == now.day &&
                  day.month == now.month &&
                  day.year == now.year;
              final isSelected = day.day == _selectedDate.day &&
                  day.month == _selectedDate.month &&
                  day.year == _selectedDate.year;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedDate = day;
                  });
                  _checkHolidayStatus();
                  _loadVisibleRangeHolidays();
                },
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isToday
                        ? const Color(0xFF00CC58).withValues(alpha: 0.2)
                        : Colors.transparent,
                    border: isToday
                        ? Border.all(color: const Color(0xFF00CC58), width: 1.5)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: isToday || isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isToday
                              ? const Color(0xFF00CC58)
                              : isCurrentMonth
                                  ? (isDarkMode
                                      ? const Color(0xFFF5F5F5)
                                      : const Color(0xFF121212))
                                  : (isDarkMode
                                      ? const Color(0xFF666666)
                                      : const Color(0xFF999999)),
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (isSelected)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00CC58),
                            shape: BoxShape.circle,
                          ),
                        ),
                      if (!isSelected) const SizedBox(height: 6),
                      // Holiday label (single line, ellipsis)
                      Builder(builder: (context) {
                        final DateTime key =
                            DateTime(day.year, day.month, day.day);
                        final String? label = _holidayByDate[key];
                        if (label == null || label.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 9,
                              color: isCurrentMonth
                                  ? (isDarkMode
                                      ? const Color(0xFFCCCCCC)
                                      : const Color(0xFF666666))
                                  : (isDarkMode
                                      ? const Color(0xFF555555)
                                      : const Color(0xFF999999)),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return months[month - 1];
  }

  Widget _buildRuleItem({
    required IconData icon,
    required String title,
    required String description,
    required bool isActive,
    required bool isDarkMode,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF1A4D2E)
            : (isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFF0F0F0)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive
              ? const Color(0xFF00CC58)
              : (isDarkMode
                  ? const Color(0xFF333333)
                  : const Color(0xFFCCCCCC)),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: isActive
                ? const Color(0xFF00CC58)
                : (isDarkMode
                    ? const Color(0xFF666666)
                    : const Color(0xFF888888)),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? const Color(0xFFF5F5F5)
                        : (isDarkMode
                            ? const Color(0xFF999999)
                            : const Color(0xFF666666)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: isActive
                        ? const Color(0xFFCCCCCC)
                        : (isDarkMode
                            ? const Color(0xFF666666)
                            : const Color(0xFF888888)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeDisplay(bool isDarkMode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Column(
        children: [
          Text(
            DateFormat('hh:mm a').format(_currentTime),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00CC58),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('EEEE, MMMM d, y').format(_currentTime),
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: isDarkMode
                  ? const Color(0xFF999999)
                  : const Color(0xFF666666),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherSection(bool isDarkMode) {
    return Consumer<WeatherProvider>(
      builder: (context, weatherProv, child) {
        final weather = weatherProv.weather;

        if (weatherProv.isLoading && weather == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: Color(0xFF00CC58)),
            ),
          );
        }

        if (weatherProv.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Icon(Icons.cloud_off,
                      color: isDarkMode ? Colors.grey : Colors.grey[600],
                      size: 32),
                  const SizedBox(height: 8),
                  Text(
                    weatherProv.error ?? "Failed to load weather",
                    style: TextStyle(
                        color: isDarkMode ? Colors.grey : Colors.grey[600]),
                  ),
                  TextButton.icon(
                    onPressed: weatherProv.retryFetch,
                    icon: const Icon(Icons.refresh, color: Color(0xFF00CC58)),
                    label: Text("Retry",
                        style: TextStyle(
                            color: isDarkMode ? Colors.white : Colors.black)),
                  )
                ],
              ),
            ),
          );
        }

        if (weather == null) {
          // If manual refresh needed or not initialized
          return Center(
              child: TextButton.icon(
            onPressed: () =>
                LocationWeatherService.refreshWeatherNow(weatherProv),
            icon: const Icon(Icons.cloud_download, color: Color(0xFF00CC58)),
            label: Text("Load Weather",
                style:
                    TextStyle(color: isDarkMode ? Colors.white : Colors.black)),
          ));
        }

        return Column(
          children: [
            // Commute Message
            _buildCommuteMessage(isDarkMode, weather),
            const SizedBox(height: 16),

            // Current Weather + Forecast
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF1A1A1A)
                    : const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDarkMode
                      ? const Color(0xFF2A2A2A)
                      : const Color(0xFFE0E0E0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CachedNetworkImage(
                        imageUrl: weather.iconUrl,
                        width: 48,
                        height: 48,
                        placeholder: (context, url) => Container(),
                        errorWidget: (context, url, error) =>
                            const Icon(Icons.cloud_off),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${weather.tempC.round()}°C',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode
                                  ? const Color(0xFFF5F5F5)
                                  : const Color(0xFF121212),
                            ),
                          ),
                          Text(
                            weather.condition,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              color: isDarkMode
                                  ? const Color(0xFF999999)
                                  : const Color(0xFF666666),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (weather.forecast.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    Text(
                      '3-Day Forecast',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode
                            ? const Color(0xFF999999)
                            : const Color(0xFF666666),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: weather.forecast.take(3).map((day) {
                        return Expanded(
                          child: Column(
                            children: [
                              Text(
                                DateFormat('E').format(day.date),
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  color: isDarkMode
                                      ? const Color(0xFF999999)
                                      : const Color(0xFF666666),
                                ),
                              ),
                              const SizedBox(height: 8),
                              CachedNetworkImage(
                                imageUrl: day.iconUrl,
                                width: 32,
                                height: 32,
                                placeholder: (context, url) =>
                                    SizedBox(width: 32, height: 32),
                                errorWidget: (context, url, error) =>
                                    const Icon(Icons.error, size: 20),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${day.maxTempC.round()}°',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isDarkMode
                                      ? const Color(0xFFF5F5F5)
                                      : const Color(0xFF121212),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCommuteMessage(bool isDarkMode, Weather weather) {
    String message;
    Color color;
    IconData icon;
    Color iconColor;
    Color bgColor;

    bool isBadWeather = weather.isRaining ||
        weather.condition.toLowerCase().contains('storm') ||
        weather.condition.toLowerCase().contains('thunder');

    if (isBadWeather) {
      if (weather.condition.toLowerCase().contains('heavy') ||
          weather.condition.toLowerCase().contains('storm')) {
        message = "Commuting might be difficult right now due to heavy rain.";
        color = Colors.redAccent;
        icon = Icons.warning_amber_rounded;
        bgColor = Colors.redAccent.withValues(alpha: 0.1);
        iconColor = Colors.redAccent;
      } else {
        message = "Bring an umbrella! It's raining.";
        color = Colors.orangeAccent;
        icon = Icons.umbrella;
        bgColor = Colors.orangeAccent.withValues(alpha: 0.1);
        iconColor = Colors.orangeAccent;
      }
    } else {
      message = "Good time to commute right now.";
      color = const Color(0xFF00CC58);
      icon = Icons.check_circle_outline;
      bgColor = const Color(0xFF00CC58).withValues(alpha: 0.1);
      iconColor = const Color(0xFF00CC58);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF1E1E1E)
            : bgColor, // Dark mode overrides colored bg for subtlety
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode
              ? color.withValues(alpha: 0.5)
              : color.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDarkMode
                    ? const Color(0xFFF5F5F5)
                    : const Color(0xFF121212),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
