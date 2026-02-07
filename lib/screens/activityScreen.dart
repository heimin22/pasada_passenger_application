import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasada_passenger_app/screens/offflineConnectionCheckService.dart';
import 'package:pasada_passenger_app/screens/viewRideDetailsScreen.dart';
import 'package:pasada_passenger_app/widgets/booking_list_item.dart';
import 'package:pasada_passenger_app/widgets/skeleton.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  // State
  List<Map<String, dynamic>> _bookings = [];
  bool _isLoading = true;
  bool _isSynced = true;
  Timer? _refreshTimer;

  // Design Constants
  static const Color _primaryColor = Color(0xFF00CC58);
  static const Color _darkBackground = Color(0xFF121212);
  static const Color _lightBackground = Color(0xFFF5F5F5);
  static const Color _darkSurface = Color(0xFF1E1E1E);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _darkText = Color(0xFFF5F5F5);
  static const Color _lightText = Color(0xFF121212);
  static const Color _darkSubText = Color(0xFFAAAAAA);
  static const Color _lightSubText = Color(0xFF515151);

  @override
  void initState() {
    super.initState();
    _fetchBookings();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchBookings() async {
    if (!mounted) return;

    // Only show full loading if we have no data yet
    if (_bookings.isEmpty) {
      setState(() => _isLoading = true);
    }

    setState(() => _isSynced = false);

    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        debugPrint('No user logged in');
        if (mounted) {
          setState(() {
            _bookings = [];
            _isLoading = false;
            _isSynced = true;
          });
        }
        return;
      }

      // Optimized query: Filter by status on the server side
      // Using .or filter for ride_status as .in_ is not available
      final response = await Supabase.instance.client
          .from('bookings')
          .select()
          .eq('passenger_id', currentUser.id)
          .or('ride_status.eq.completed,ride_status.eq.accepted,ride_status.eq.ongoing')
          .order('created_at', ascending: false)
          .limit(20); // Limit to 20 for better initial load performance

      if (mounted) {
        setState(() {
          _bookings = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
          _isSynced = true;
        });
      }
    } catch (e) {
      debugPrint('Error fetching bookings: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSynced = false;
        });
      }
    }
  }

  void _viewBookingDetails(Map<String, dynamic> booking) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewRideDetailsScreen(booking: booking),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Set system UI overlay style
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        systemNavigationBarColor:
            isDarkMode ? _darkBackground : _lightBackground,
        systemNavigationBarIconBrightness:
            isDarkMode ? Brightness.light : Brightness.dark,
        statusBarColor: Colors.transparent,
      ),
    );

    return Scaffold(
      backgroundColor: isDarkMode ? _darkBackground : _lightBackground,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchBookings,
          color: _primaryColor,
          backgroundColor: isDarkMode ? _darkSurface : _lightSurface,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _buildSliverAppBar(isDarkMode),
              SliverToBoxAdapter(
                child: _buildConnectivityBanner(isDarkMode),
              ),
              if (_isLoading)
                SliverFillRemaining(
                  child: _buildLoadingState(context),
                )
              else if (_bookings.isEmpty)
                SliverFillRemaining(
                  child: _buildEmptyState(isDarkMode),
                )
              else
                _buildBookingList(isDarkMode),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(bool isDarkMode) {
    return SliverAppBar(
      expandedHeight: 100.0,
      floating: false,
      pinned: true,
      backgroundColor: isDarkMode ? _darkBackground : _lightBackground,
      elevation: 0,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        title: Text(
          'Activity',
          style: TextStyle(
            color: isDarkMode ? _darkText : _lightText,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            fontFamily: 'Inter',
          ),
        ),
        centerTitle: false,
      ),
    );
  }

  Widget _buildConnectivityBanner(bool isDarkMode) {
    final connectivityService = OfflineConnectionCheckService();
    return StreamBuilder<bool>(
      stream: connectivityService.connectionStream,
      initialData: connectivityService.isConnected,
      builder: (context, snapshot) {
        final online = snapshot.data ?? true;
        final showBanner = !online || !_isSynced;

        if (!showBanner) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFD7481D).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: const Color(0xFFD7481D).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.cloud_off_rounded,
                  color: Color(0xFFD7481D), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  online
                      ? 'Data may be out of date. Pull to refresh.'
                      : 'You are offline. Showing last known data.',
                  style: TextStyle(
                    color: isDarkMode ? _darkText : _lightText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBookingList(bool isDarkMode) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final booking = _bookings[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () => _viewBookingDetails(booking),
                child: BookingListItem(booking: booking),
              ),
            );
          },
          childCount: _bookings.length,
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListSkeleton(
        itemCount: 6,
        screenWidth: screenWidth,
        itemPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }

  Widget _buildEmptyState(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.history_rounded,
              size: 48,
              color: _primaryColor,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Recent Activity',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDarkMode ? _darkText : _lightText,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Your completed and ongoing rides will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? _darkSubText : _lightSubText,
                fontFamily: 'Inter',
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
