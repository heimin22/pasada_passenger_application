import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pasada_passenger_app/services/polyline_cache_service.dart';
import 'package:pasada_passenger_app/services/route_service.dart';
import 'package:pasada_passenger_app/services/traffic_service.dart';
import 'package:pasada_passenger_app/widgets/alert_sequence_dialog.dart';
import 'package:pasada_passenger_app/widgets/rush_hour_dialog.dart';
import 'package:pasada_passenger_app/widgets/skeleton.dart';
import 'package:pasada_passenger_app/widgets/traffic_insights_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RouteSelection extends StatefulWidget {
  const RouteSelection({super.key});

  @override
  State<RouteSelection> createState() => _RouteSelectionState();
}

class _RouteSelectionState extends State<RouteSelection> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _routes = [];
  List<Map<String, dynamic>> _filteredRoutes = [];
  bool _isLoading = true;

  // Design constants
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
    _loadRoutes();
    _searchController.addListener(_filterRoutes);
  }

  void _filterRoutes() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredRoutes = _routes.where((route) {
        final routeName = route['route_name'].toString().toLowerCase();
        final description = route['description'].toString().toLowerCase();
        return routeName.contains(query) || description.contains(query);
      }).toList();
    });
  }

  Future<void> _loadRoutes() async {
    try {
      setState(() => _isLoading = true);

      final response = await Supabase.instance.client
          .from('official_routes')
          .select(
              'route_name, description, origin_lat, origin_lng, destination_lat, destination_lng, intermediate_coordinates, origin_name, destination_name, status')
          .eq('status', 'active')
          .order('route_name');

      if (response.isNotEmpty) {
        final statuses = response.map((route) => route['status']).toSet();
        debugPrint('Available statuses: $statuses');
      } else {
        debugPrint('No routes found in the database');
        if (mounted) {
          setState(() {
            _routes = [];
            _filteredRoutes = [];
            _isLoading = false;
          });
          _showToast('No routes available');
        }
        return;
      }

      if (mounted) {
        setState(() {
          _routes = List<Map<String, dynamic>>.from(response);
          _filteredRoutes = _routes;
          _isLoading = false;
        });
      }
    } catch (error) {
      debugPrint("Error loading routes: $error");
      if (mounted) {
        setState(() => _isLoading = false);
        _showToast('Error loading routes: $error');
      }
    }
  }

  void _showToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: _lightBackground,
      textColor: _lightText,
    );
  }

  Future<void> _selectRoute(Map<String, dynamic> route) async {
    // Make sure the route has an ID field
    if (route['officialroute_id'] == null) {
      try {
        final routeDetails = await Supabase.instance.client
            .from('official_routes')
            .select('officialroute_id')
            .eq('route_name', route['route_name'])
            .single();

        if (routeDetails.isNotEmpty) {
          route['officialroute_id'] = routeDetails['officialroute_id'];
        }
      } catch (e) {
        debugPrint('Error retrieving route ID: $e');
      }
    }

    // Process coordinates and get polyline before returning
    if (route['origin_lat'] != null &&
        route['origin_lng'] != null &&
        route['destination_lat'] != null &&
        route['destination_lng'] != null) {
      final originLatLng = LatLng(
        double.parse(route['origin_lat'].toString()),
        double.parse(route['origin_lng'].toString()),
      );

      final destinationLatLng = LatLng(
        double.parse(route['destination_lat'].toString()),
        double.parse(route['destination_lng'].toString()),
      );

      route['origin_coordinates'] = originLatLng;
      route['destination_coordinates'] = destinationLatLng;

      // Process intermediate coordinates
      if (route['intermediate_coordinates'] != null) {
        if (route['intermediate_coordinates'] is String) {
          try {
            route['intermediate_coordinates'] =
                jsonDecode(route['intermediate_coordinates']);
          } catch (e) {
            debugPrint('Failed to parse intermediate_coordinates: $e');
          }
        }

        try {
          final polylineCacheService = PolylineCacheService();
          final polylineCoordinates =
              await polylineCacheService.getPolylineCoordinates(
            origin: originLatLng,
            destination: destinationLatLng,
            intermediatePoints: route['intermediate_coordinates'],
          );
          route['polyline_coordinates'] = polylineCoordinates;
        } catch (e) {
          debugPrint('Error getting polyline: $e');
        }
      }
    }

    // Show heavy traffic alert if density is high
    if (mounted &&
        route.containsKey('origin_coordinates') &&
        route.containsKey('destination_coordinates')) {
      final origin = route['origin_coordinates'] as LatLng;
      final destination = route['destination_coordinates'] as LatLng;
      final isHeavyTraffic =
          await TrafficService().isRouteUnderHeavyTraffic(origin, destination);
      if (isHeavyTraffic && mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertSequenceDialog(
            pages: const [RushHourDialogContent()],
          ),
        );
      }
    }

    // Save the route for persistence
    await RouteService.saveRoute(route);

    if (mounted) {
      Navigator.pop(context, route);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? _darkBackground : _lightBackground,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(isDarkMode),
          _buildSearchSliver(isDarkMode),
          if (_isLoading)
            SliverFillRemaining(
              child: _buildLoadingState(context),
            )
          else if (_filteredRoutes.isEmpty)
            SliverFillRemaining(
              child: _buildEmptyState(isDarkMode),
            )
          else
            _buildRouteList(isDarkMode),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            showTrafficInsightsSheet(context, _routes, _filteredRoutes),
        icon: const Icon(Icons.traffic_rounded),
        label: const Text(
          'Traffic Insights',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor:
            isDarkMode ? const Color(0xFFFFCE21) : const Color(0xFF067837),
        foregroundColor:
            isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
        elevation: 4,
      ),
    );
  }

  Widget _buildSliverAppBar(bool isDarkMode) {
    return SliverAppBar(
      expandedHeight: 120.0,
      floating: false,
      pinned: true,
      backgroundColor: isDarkMode ? _darkBackground : _lightBackground,
      elevation: 0,
      leading: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: CircleAvatar(
          backgroundColor: isDarkMode ? _darkSurface : _lightSurface,
          child: IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: isDarkMode ? _darkText : _lightText,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
        title: Text(
          'Select Route',
          style: TextStyle(
            color: isDarkMode ? _darkText : _lightText,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            fontFamily: 'Inter',
          ),
        ),
        centerTitle: false,
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: CircleAvatar(
            backgroundColor: isDarkMode ? _darkSurface : _lightSurface,
            child: Icon(
              Icons.map_outlined,
              color: isDarkMode ? _darkText : _lightText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchSliver(bool isDarkMode) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _SliverSearchDelegate(
        isDarkMode: isDarkMode,
        controller: _searchController,
      ),
    );
  }

  Widget _buildRouteList(bool isDarkMode) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Available Routes',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? _darkText : _lightText,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_filteredRoutes.length} Active',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            final route = _filteredRoutes[index - 1];
            return _RouteCard(
              route: route,
              isDarkMode: isDarkMode,
              onTap: () => _selectRoute(route),
            );
          },
          childCount: _filteredRoutes.length + 1,
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
          Icon(
            Icons.search_off_rounded,
            size: 64,
            color:
                isDarkMode ? const Color(0xFF333333) : const Color(0xFFCCCCCC),
          ),
          const SizedBox(height: 16),
          Text(
            'No routes found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDarkMode ? _darkText : _lightText,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try searching for a different route',
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode ? _darkSubText : _lightSubText,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}

class _SliverSearchDelegate extends SliverPersistentHeaderDelegate {
  final bool isDarkMode;
  final TextEditingController controller;

  _SliverSearchDelegate({
    required this.isDarkMode,
    required this.controller,
  });

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: isDarkMode
          ? const Color(0xFF121212)
          : const Color(0xFFF5F5F5), // Match scaffold background
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
        style: TextStyle(
          fontFamily: 'Inter',
          color: isDarkMode ? const Color(0xFFF5F5F5) : const Color(0xFF121212),
        ),
        decoration: InputDecoration(
          hintText: 'Search for a route...',
          hintStyle: TextStyle(
            fontFamily: 'Inter',
            color:
                isDarkMode ? const Color(0xFFAAAAAA) : const Color(0xFF515151),
          ),
          prefixIcon: Icon(
            Icons.search,
            color:
                isDarkMode ? const Color(0xFFAAAAAA) : const Color(0xFF515151),
          ),
          filled: true,
          fillColor:
              isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  @override
  double get maxExtent => 70;

  @override
  double get minExtent => 70;

  @override
  bool shouldRebuild(_SliverSearchDelegate oldDelegate) {
    return isDarkMode != oldDelegate.isDarkMode;
  }
}

class _RouteCard extends StatelessWidget {
  final Map<String, dynamic> route;
  final bool isDarkMode;
  final VoidCallback onTap;

  const _RouteCard({
    required this.route,
    required this.isDarkMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00CC58).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.directions_bus_rounded,
                        color: Color(0xFF00CC58),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            route['route_name'] ?? 'Unnamed Route',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDarkMode
                                  ? const Color(0xFFF5F5F5)
                                  : const Color(0xFF121212),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            route['description'] ?? 'No description available',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              height: 1.4,
                              color: isDarkMode
                                  ? const Color(0xFFAAAAAA)
                                  : const Color(0xFF666666),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF00CC58),
                    ),
                  ],
                ),
                if (route['origin_name'] != null ||
                    route['destination_name'] != null) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildLocationPill(
                        context,
                        route['origin_name'] ?? 'Origin',
                        Icons.my_location_rounded,
                        isDarkMode,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: isDarkMode
                              ? const Color(0xFF555555)
                              : const Color(0xFFAAAAAA),
                        ),
                      ),
                      _buildLocationPill(
                        context,
                        route['destination_name'] ?? 'Destination',
                        Icons.location_on_rounded,
                        isDarkMode,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationPill(
      BuildContext context, String text, IconData icon, bool isDarkMode) {
    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isDarkMode
                ? const Color(0xFF00CC58)
                : const Color(
                    0xFF00883A), // Slightly darker green for light mode
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDarkMode
                    ? const Color(0xFFCCCCCC)
                    : const Color(0xFF555555),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
