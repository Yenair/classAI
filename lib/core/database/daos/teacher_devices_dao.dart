// lib/core/database/daos/teacher_devices_dao.dart
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/teacher_devices.dart';

part 'teacher_devices_dao.g.dart';

@DriftAccessor(tables: [TeacherDevices])
class TeacherDevicesDao extends DatabaseAccessor<AppDatabase>
    with _$TeacherDevicesDaoMixin {
  TeacherDevicesDao(AppDatabase db) : super(db);

  /// Get all devices for a teacher.
  Future<List<TeacherDevice>> getByTeacher(int teacherLocalId) {
    return (select(teacherDevices)
          ..where((t) => t.teacherId.equals(teacherLocalId))
          ..orderBy([(t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc)]))
        .get();
  }

  /// Count active devices for a teacher.
  Future<int> countActiveByTeacher(int teacherLocalId) async {
    final rows = await (select(teacherDevices)
          ..where((t) => t.teacherId.equals(teacherLocalId))
          ..where((t) => t.isActive.equals(true)))
        .get();
    return rows.length;
  }

  /// Insert a device record.
  Future<int> insert({
    required int teacherId,
    required String deviceId,
    required String deviceName,
    required String platform,
    String? lastActive,
    bool isActive = true,
  }) async {
    return into(teacherDevices).insert(
      TeacherDevicesCompanion.insert(
        teacherId: teacherId,
        deviceId: deviceId,
        deviceName: deviceName,
        platform: platform,
        lastActive: lastActive != null ? Value(lastActive) : const Value.absent(),
        isActive: Value(isActive),
      ),
    );
  }

  /// Deactivate a device.
  Future<void> deactivate(int deviceId) async {
    await (update(teacherDevices)..where((t) => t.id.equals(deviceId))).write(
      const TeacherDevicesCompanion(
        isActive: Value(false),
      ),
    );
  }

  /// Update last_active timestamp for a device.
  Future<void> updateLastActive(int deviceId, String timestamp) async {
    await (update(teacherDevices)..where((t) => t.id.equals(deviceId))).write(
      TeacherDevicesCompanion(
        lastActive: Value(timestamp),
      ),
    );
  }

  /// Hard-delete all device records for a given teacher.
  /// Used during logout to clean re-downloadable device data.
  Future<void> deleteAllByTeacher(int teacherLocalId) {
    return (delete(teacherDevices)
          ..where((t) => t.teacherId.equals(teacherLocalId)))
        .go();
  }
}
