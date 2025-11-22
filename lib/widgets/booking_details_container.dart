import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../location/selectedLocation.dart';
import '../utils/booking_id_utils.dart';

class BookingDetailsContainer extends StatelessWidget {
  final SelectedLocation? pickupLocation;
  final SelectedLocation? dropoffLocation;
  final int? bookingId;
  final double? fare;
  final String? selectedDiscount;
  final String? capturedImageUrl;

  const BookingDetailsContainer({
    super.key,
    required this.pickupLocation,
    required this.dropoffLocation,
    this.bookingId,
    this.fare,
    this.selectedDiscount,
    this.capturedImageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Booking Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDarkMode
                  ? const Color(0xFFF5F5F5)
                  : const Color(0xFF121212),
            ),
          ),
          const SizedBox(height: 16),

          // Booking ID Section
          if (bookingId != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF2A2A2A)
                    : const Color(0xFFE8F5E8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF00CC58).withAlpha(0.3.toInt()),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.receipt_outlined,
                        color: const Color(0xFF00CC58),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Booking ID: ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDarkMode
                              ? const Color(0xFFBBBBBB)
                              : const Color(0xFF666666),
                        ),
                      ),
                      Text(
                        '#${BookingIdUtils.formatBookingId(bookingId!)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF00CC58),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_outlined, size: 18),
                    color: isDarkMode
                        ? const Color(0xFFBBBBBB)
                        : const Color(0xFF666666),
                    tooltip: 'Share tracking link',
                    onPressed: () {
                      final id = bookingId!; // safe due to guard above
                      final url = 'https://pasadaapp.com/track/$id';
                      SharePlus.instance.share(
                        ShareParams(
                          text: 'Boss, ito yung link ng booking ko: $url',
                          subject: 'Track my Pasada booking',
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          _buildLocationRow(
            context,
            'Pick-up',
            pickupLocation?.address ?? 'Unknown location',
            Icons.location_on_outlined,
            isDarkMode,
          ),
          const SizedBox(height: 16),
          _buildLocationRow(
            context,
            'Drop-off',
            dropoffLocation?.address ?? 'Unknown location',
            Icons.location_on,
            isDarkMode,
          ),

          // Discount and ID Picture Section
          if (selectedDiscount != null &&
              selectedDiscount!.isNotEmpty &&
              selectedDiscount != 'None') ...[
            const SizedBox(height: 16),
            Row(
              children: [
                // Discount Info
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.orange.withAlpha(0.3.toInt()),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.discount_outlined,
                              color: Colors.orange,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Discount Applied',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isDarkMode
                                    ? const Color(0xFFBBBBBB)
                                    : const Color(0xFF666666),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          selectedDiscount!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ID Picture Preview
                if (capturedImageUrl != null &&
                    capturedImageUrl!.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF00CC58).withAlpha(0.3.toInt()),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: CachedNetworkImage(
                        imageUrl: capturedImageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: isDarkMode
                              ? const Color(0xFF3A3A3A)
                              : const Color(0xFFF0F0F0),
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF00CC58),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) {
                          return Container(
                            color: isDarkMode
                                ? const Color(0xFF2A2A2A)
                                : const Color(0xFFF0F0F0),
                            child: Icon(
                              Icons.image_outlined,
                              color: isDarkMode
                                  ? const Color(0xFFBBBBBB)
                                  : const Color(0xFF666666),
                              size: 24,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationRow(BuildContext context, String title, String value,
      IconData icon, bool isDarkMode) {
    return Row(
      children: [
        Icon(
          icon,
          size: 24,
          color: const Color(0xFF00CC58),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: isDarkMode
                      ? const Color(0xFFAAAAAA)
                      : const Color(0xFF515151),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode
                      ? const Color(0xFFF5F5F5)
                      : const Color(0xFF121212),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
