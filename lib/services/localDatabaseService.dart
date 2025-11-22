import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'bookingDetails.dart';

class LocalDatabaseService {
  static Database? database;
  static const String dbName = 'passenger_bookings.db';
  static const String tableName = 'bookings';

  Future<Database> get BookingDatabase async {
    if (database != null) return database!;
    database = await initDatabase();
    return database!;
  }

  Future<Database> initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, dbName);

    return await openDatabase(
      path,
      version: 3,
      onCreate: onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // Migration for version upgrade: drop and recreate the bookings table
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS $tableName');
      await onCreate(db, newVersion);
    } else if (oldVersion < 3) {
      await db.execute(
          "ALTER TABLE $tableName ADD COLUMN seat_type TEXT NOT NULL DEFAULT 'Any'");
    }
  }

  // table creation for the local database
  Future<void> onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableName (
        booking_id INTEGER PRIMARY KEY,
        driver_id INTEGER NOT NULL,
        route_id INTEGER NOT NULL,
        ride_status TEXT NOT NULL CHECK(ride_status IN ('accepted', 'ongoing', 'completed', 'cancelled')),
        pickup_address TEXT NOT NULL,
        pickup_lat REAL NOT NULL,
        pickup_lng REAL NOT NULL,
        dropoff_address TEXT NOT NULL,
        dropoff_lat REAL NOT NULL,
        dropoff_lng REAL NOT NULL,
        start_time TEXT NOT NULL,
        created_at TEXT NOT NULL,
        fare REAL NOT NULL,
        seat_type TEXT NOT NULL,
        assigned_at TEXT NOT NULL,
        end_time TEXT NOT NULL,
        passenger_id TEXT NOT NULL
      )
    ''');
    debugPrint("Local SQLite table '$tableName' created.");
  }

  // saves or updates the booking details locally
  Future<void> saveBookingDetails(BookingDetails details) async {
    try {
      final db = await BookingDatabase;
      await db.insert(
        tableName,
        details.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('Saved booking ${details.bookingId} to local DB');
    } catch (e) {
      debugPrint('Error saving booking ${details.bookingId} locally: $e');
    }
  }

  // retrieves booking details from the local database
  Future<BookingDetails?> getBookingDetails(int bookingId) async {
    try {
      final db = await BookingDatabase;
      final List<Map<String, dynamic>> maps = await db.query(
        tableName,
        where: 'booking_id = ?',
        whereArgs: [bookingId],
      );

      if (maps.isNotEmpty) {
        debugPrint("Retrieved booking $bookingId from local DB.");
        return BookingDetails.fromMap(maps.first);
      }
      debugPrint("Booking $bookingId not found in local DB.");
      return null;
    } catch (e) {
      debugPrint('Error retrieving booking $bookingId locally: $e');
      return null;
    }
  }

  // updates the status ng local booking record
  Future<void> updateLocalBookingStatus(int bookingId, String newStatus) async {
    try {
      final db = await BookingDatabase;

      // If status is 'requested', delete the local booking entry
      // because local DB only stores bookings with driver assigned (accepted, ongoing, completed, cancelled)
      if (newStatus == 'requested') {
        final count = await db.delete(
          tableName,
          where: 'booking_id = ?',
          whereArgs: [bookingId],
        );
        if (count > 0) {
          debugPrint(
              'Deleted local booking $bookingId (status reset to requested).');
        } else {
          debugPrint("Local booking $bookingId not found for deletion.");
        }
        return;
      }

      // For other statuses, update normally
      int count = await db.update(
        tableName,
        {'ride_status': newStatus},
        where: 'booking_id = ?',
        whereArgs: [bookingId],
      );
      if (count > 0) {
        debugPrint(
            'Updated status for local booking $bookingId to $newStatus.');
      }
      // Silently handle case where booking doesn't exist in local DB
      // This is normal if booking was never saved locally or was already deleted
    } catch (e) {
      debugPrint("Error updating status for local booking $bookingId: $e");
    }
  }

  // deletes booking details from the local database
  Future<void> deleteBookingDetails(int bookingId) async {
    try {
      final db = await BookingDatabase;
      await db.delete(
        tableName,
        where: 'booking_id = ?',
        whereArgs: [bookingId],
      );
      debugPrint("Deleted booking $bookingId from local DB.");
    } catch (e) {
      debugPrint("Error deleting booking $bookingId locally: $e");
    }
  }
}
