import 'package:flutter/material.dart';

class PaymentDetailsContainer extends StatelessWidget {
  final String paymentMethod;
  final VoidCallback onCancelBooking;
  final double fare;
  final String seatingPreference;
  final bool showCancelButton;

  const PaymentDetailsContainer({
    super.key,
    required this.paymentMethod,
    required this.onCancelBooking,
    this.fare = 15.0,
    this.seatingPreference = '',
    this.showCancelButton = true,
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
          // Title
          Text(
            'Payment Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'Inter',
              color: isDarkMode
                  ? const Color(0xFFF5F5F5)
                  : const Color(0xFF121212),
            ),
          ),
          const SizedBox(height: 20),

          // Payment Method Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? const Color(0xFF2A2A2A)
                  : const Color(0xFFF0FFF5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF00CC58).withAlpha(0.3.toInt()),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00CC58).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.payment_rounded,
                    size: 24,
                    color: Color(0xFF00CC58),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment Method',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Inter',
                          color: isDarkMode
                              ? const Color(0xFFBBBBBB)
                              : const Color(0xFF666666),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        paymentMethod,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter',
                          color: isDarkMode
                              ? const Color(0xFFF5F5F5)
                              : const Color(0xFF121212),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Fare Section
          Container(
            padding: const EdgeInsets.all(16),
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
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00CC58).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '₱',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Inter',
                          color: Color(0xFF00CC58),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Fare',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Inter',
                            color: isDarkMode
                                ? const Color(0xFFBBBBBB)
                                : const Color(0xFF666666),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₱${fare.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Inter',
                            color: Color(0xFF00CC58),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
