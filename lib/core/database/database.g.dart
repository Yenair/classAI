// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $SchoolsTable extends Schools with TableInfo<$SchoolsTable, School> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SchoolsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta =
      const VerificationMeta('localId');
  @override
  late final GeneratedColumn<int> localId = GeneratedColumn<int>(
      'local_id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _serverIdMeta =
      const VerificationMeta('serverId');
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
      'server_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _schoolNameMeta =
      const VerificationMeta('schoolName');
  @override
  late final GeneratedColumn<String> schoolName = GeneratedColumn<String>(
      'school_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _shortCodeMeta =
      const VerificationMeta('shortCode');
  @override
  late final GeneratedColumn<String> shortCode = GeneratedColumn<String>(
      'short_code', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _logoUrlMeta =
      const VerificationMeta('logoUrl');
  @override
  late final GeneratedColumn<String> logoUrl = GeneratedColumn<String>(
      'logo_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _subscriptionTierMeta =
      const VerificationMeta('subscriptionTier');
  @override
  late final GeneratedColumn<String> subscriptionTier = GeneratedColumn<String>(
      'subscription_tier', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('free'));
  static const VerificationMeta _activeCurriculumMeta =
      const VerificationMeta('activeCurriculum');
  @override
  late final GeneratedColumn<String> activeCurriculum = GeneratedColumn<String>(
      'active_curriculum', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('nerdc'));
  static const VerificationMeta _activeCurriculumVersionMeta =
      const VerificationMeta('activeCurriculumVersion');
  @override
  late final GeneratedColumn<String> activeCurriculumVersion =
      GeneratedColumn<String>('active_curriculum_version', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _totalSeatsMeta =
      const VerificationMeta('totalSeats');
  @override
  late final GeneratedColumn<int> totalSeats = GeneratedColumn<int>(
      'total_seats', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(5));
  static const VerificationMeta _schoolMasterKeyWrappedMeta =
      const VerificationMeta('schoolMasterKeyWrapped');
  @override
  late final GeneratedColumn<String> schoolMasterKeyWrapped =
      GeneratedColumn<String>('school_master_key_wrapped', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _adminRecoveryEmailMeta =
      const VerificationMeta('adminRecoveryEmail');
  @override
  late final GeneratedColumn<String> adminRecoveryEmail =
      GeneratedColumn<String>('admin_recovery_email', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _adminRecoveryEmailVerifiedMeta =
      const VerificationMeta('adminRecoveryEmailVerified');
  @override
  late final GeneratedColumn<bool> adminRecoveryEmailVerified =
      GeneratedColumn<bool>('admin_recovery_email_verified', aliasedName, false,
          type: DriftSqlType.bool,
          requiredDuringInsert: false,
          defaultConstraints: GeneratedColumn.constraintIsAlways(
              'CHECK ("admin_recovery_email_verified" IN (0, 1))'),
          defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updateCounterMeta =
      const VerificationMeta('updateCounter');
  @override
  late final GeneratedColumn<int> updateCounter = GeneratedColumn<int>(
      'update_counter', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isDeletedMeta =
      const VerificationMeta('isDeleted');
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
      'is_deleted', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_deleted" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _lastModifiedByMeta =
      const VerificationMeta('lastModifiedBy');
  @override
  late final GeneratedColumn<String> lastModifiedBy = GeneratedColumn<String>(
      'last_modified_by', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        localId,
        serverId,
        schoolName,
        shortCode,
        logoUrl,
        subscriptionTier,
        activeCurriculum,
        activeCurriculumVersion,
        totalSeats,
        schoolMasterKeyWrapped,
        adminRecoveryEmail,
        adminRecoveryEmailVerified,
        createdAt,
        updatedAt,
        updateCounter,
        isDeleted,
        lastModifiedBy
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'schools';
  @override
  VerificationContext validateIntegrity(Insertable<School> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(_localIdMeta,
          localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta));
    }
    if (data.containsKey('server_id')) {
      context.handle(_serverIdMeta,
          serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta));
    }
    if (data.containsKey('school_name')) {
      context.handle(
          _schoolNameMeta,
          schoolName.isAcceptableOrUnknown(
              data['school_name']!, _schoolNameMeta));
    } else if (isInserting) {
      context.missing(_schoolNameMeta);
    }
    if (data.containsKey('short_code')) {
      context.handle(_shortCodeMeta,
          shortCode.isAcceptableOrUnknown(data['short_code']!, _shortCodeMeta));
    } else if (isInserting) {
      context.missing(_shortCodeMeta);
    }
    if (data.containsKey('logo_url')) {
      context.handle(_logoUrlMeta,
          logoUrl.isAcceptableOrUnknown(data['logo_url']!, _logoUrlMeta));
    }
    if (data.containsKey('subscription_tier')) {
      context.handle(
          _subscriptionTierMeta,
          subscriptionTier.isAcceptableOrUnknown(
              data['subscription_tier']!, _subscriptionTierMeta));
    }
    if (data.containsKey('active_curriculum')) {
      context.handle(
          _activeCurriculumMeta,
          activeCurriculum.isAcceptableOrUnknown(
              data['active_curriculum']!, _activeCurriculumMeta));
    }
    if (data.containsKey('active_curriculum_version')) {
      context.handle(
          _activeCurriculumVersionMeta,
          activeCurriculumVersion.isAcceptableOrUnknown(
              data['active_curriculum_version']!,
              _activeCurriculumVersionMeta));
    }
    if (data.containsKey('total_seats')) {
      context.handle(
          _totalSeatsMeta,
          totalSeats.isAcceptableOrUnknown(
              data['total_seats']!, _totalSeatsMeta));
    }
    if (data.containsKey('school_master_key_wrapped')) {
      context.handle(
          _schoolMasterKeyWrappedMeta,
          schoolMasterKeyWrapped.isAcceptableOrUnknown(
              data['school_master_key_wrapped']!, _schoolMasterKeyWrappedMeta));
    }
    if (data.containsKey('admin_recovery_email')) {
      context.handle(
          _adminRecoveryEmailMeta,
          adminRecoveryEmail.isAcceptableOrUnknown(
              data['admin_recovery_email']!, _adminRecoveryEmailMeta));
    }
    if (data.containsKey('admin_recovery_email_verified')) {
      context.handle(
          _adminRecoveryEmailVerifiedMeta,
          adminRecoveryEmailVerified.isAcceptableOrUnknown(
              data['admin_recovery_email_verified']!,
              _adminRecoveryEmailVerifiedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('update_counter')) {
      context.handle(
          _updateCounterMeta,
          updateCounter.isAcceptableOrUnknown(
              data['update_counter']!, _updateCounterMeta));
    }
    if (data.containsKey('is_deleted')) {
      context.handle(_isDeletedMeta,
          isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta));
    }
    if (data.containsKey('last_modified_by')) {
      context.handle(
          _lastModifiedByMeta,
          lastModifiedBy.isAcceptableOrUnknown(
              data['last_modified_by']!, _lastModifiedByMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  School map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return School(
      localId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}local_id'])!,
      serverId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}server_id']),
      schoolName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}school_name'])!,
      shortCode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}short_code'])!,
      logoUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}logo_url']),
      subscriptionTier: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}subscription_tier'])!,
      activeCurriculum: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}active_curriculum'])!,
      activeCurriculumVersion: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}active_curriculum_version']),
      totalSeats: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total_seats'])!,
      schoolMasterKeyWrapped: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}school_master_key_wrapped']),
      adminRecoveryEmail: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}admin_recovery_email']),
      adminRecoveryEmailVerified: attachedDatabase.typeMapping.read(
          DriftSqlType.bool,
          data['${effectivePrefix}admin_recovery_email_verified'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      updateCounter: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}update_counter'])!,
      isDeleted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_deleted'])!,
      lastModifiedBy: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}last_modified_by']),
    );
  }

  @override
  $SchoolsTable createAlias(String alias) {
    return $SchoolsTable(attachedDatabase, alias);
  }
}

class School extends DataClass implements Insertable<School> {
  final int localId;
  final String? serverId;
  final String schoolName;
  final String shortCode;
  final String? logoUrl;
  final String subscriptionTier;
  final String activeCurriculum;
  final String? activeCurriculumVersion;
  final int totalSeats;
  final String? schoolMasterKeyWrapped;
  final String? adminRecoveryEmail;
  final bool adminRecoveryEmailVerified;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int updateCounter;
  final bool isDeleted;
  final String? lastModifiedBy;
  const School(
      {required this.localId,
      this.serverId,
      required this.schoolName,
      required this.shortCode,
      this.logoUrl,
      required this.subscriptionTier,
      required this.activeCurriculum,
      this.activeCurriculumVersion,
      required this.totalSeats,
      this.schoolMasterKeyWrapped,
      this.adminRecoveryEmail,
      required this.adminRecoveryEmailVerified,
      required this.createdAt,
      required this.updatedAt,
      required this.updateCounter,
      required this.isDeleted,
      this.lastModifiedBy});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_id'] = Variable<int>(localId);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    map['school_name'] = Variable<String>(schoolName);
    map['short_code'] = Variable<String>(shortCode);
    if (!nullToAbsent || logoUrl != null) {
      map['logo_url'] = Variable<String>(logoUrl);
    }
    map['subscription_tier'] = Variable<String>(subscriptionTier);
    map['active_curriculum'] = Variable<String>(activeCurriculum);
    if (!nullToAbsent || activeCurriculumVersion != null) {
      map['active_curriculum_version'] =
          Variable<String>(activeCurriculumVersion);
    }
    map['total_seats'] = Variable<int>(totalSeats);
    if (!nullToAbsent || schoolMasterKeyWrapped != null) {
      map['school_master_key_wrapped'] =
          Variable<String>(schoolMasterKeyWrapped);
    }
    if (!nullToAbsent || adminRecoveryEmail != null) {
      map['admin_recovery_email'] = Variable<String>(adminRecoveryEmail);
    }
    map['admin_recovery_email_verified'] =
        Variable<bool>(adminRecoveryEmailVerified);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['update_counter'] = Variable<int>(updateCounter);
    map['is_deleted'] = Variable<bool>(isDeleted);
    if (!nullToAbsent || lastModifiedBy != null) {
      map['last_modified_by'] = Variable<String>(lastModifiedBy);
    }
    return map;
  }

  SchoolsCompanion toCompanion(bool nullToAbsent) {
    return SchoolsCompanion(
      localId: Value(localId),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      schoolName: Value(schoolName),
      shortCode: Value(shortCode),
      logoUrl: logoUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(logoUrl),
      subscriptionTier: Value(subscriptionTier),
      activeCurriculum: Value(activeCurriculum),
      activeCurriculumVersion: activeCurriculumVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(activeCurriculumVersion),
      totalSeats: Value(totalSeats),
      schoolMasterKeyWrapped: schoolMasterKeyWrapped == null && nullToAbsent
          ? const Value.absent()
          : Value(schoolMasterKeyWrapped),
      adminRecoveryEmail: adminRecoveryEmail == null && nullToAbsent
          ? const Value.absent()
          : Value(adminRecoveryEmail),
      adminRecoveryEmailVerified: Value(adminRecoveryEmailVerified),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      updateCounter: Value(updateCounter),
      isDeleted: Value(isDeleted),
      lastModifiedBy: lastModifiedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(lastModifiedBy),
    );
  }

  factory School.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return School(
      localId: serializer.fromJson<int>(json['localId']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      schoolName: serializer.fromJson<String>(json['schoolName']),
      shortCode: serializer.fromJson<String>(json['shortCode']),
      logoUrl: serializer.fromJson<String?>(json['logoUrl']),
      subscriptionTier: serializer.fromJson<String>(json['subscriptionTier']),
      activeCurriculum: serializer.fromJson<String>(json['activeCurriculum']),
      activeCurriculumVersion:
          serializer.fromJson<String?>(json['activeCurriculumVersion']),
      totalSeats: serializer.fromJson<int>(json['totalSeats']),
      schoolMasterKeyWrapped:
          serializer.fromJson<String?>(json['schoolMasterKeyWrapped']),
      adminRecoveryEmail:
          serializer.fromJson<String?>(json['adminRecoveryEmail']),
      adminRecoveryEmailVerified:
          serializer.fromJson<bool>(json['adminRecoveryEmailVerified']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updateCounter: serializer.fromJson<int>(json['updateCounter']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      lastModifiedBy: serializer.fromJson<String?>(json['lastModifiedBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localId': serializer.toJson<int>(localId),
      'serverId': serializer.toJson<String?>(serverId),
      'schoolName': serializer.toJson<String>(schoolName),
      'shortCode': serializer.toJson<String>(shortCode),
      'logoUrl': serializer.toJson<String?>(logoUrl),
      'subscriptionTier': serializer.toJson<String>(subscriptionTier),
      'activeCurriculum': serializer.toJson<String>(activeCurriculum),
      'activeCurriculumVersion':
          serializer.toJson<String?>(activeCurriculumVersion),
      'totalSeats': serializer.toJson<int>(totalSeats),
      'schoolMasterKeyWrapped':
          serializer.toJson<String?>(schoolMasterKeyWrapped),
      'adminRecoveryEmail': serializer.toJson<String?>(adminRecoveryEmail),
      'adminRecoveryEmailVerified':
          serializer.toJson<bool>(adminRecoveryEmailVerified),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updateCounter': serializer.toJson<int>(updateCounter),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'lastModifiedBy': serializer.toJson<String?>(lastModifiedBy),
    };
  }

  School copyWith(
          {int? localId,
          Value<String?> serverId = const Value.absent(),
          String? schoolName,
          String? shortCode,
          Value<String?> logoUrl = const Value.absent(),
          String? subscriptionTier,
          String? activeCurriculum,
          Value<String?> activeCurriculumVersion = const Value.absent(),
          int? totalSeats,
          Value<String?> schoolMasterKeyWrapped = const Value.absent(),
          Value<String?> adminRecoveryEmail = const Value.absent(),
          bool? adminRecoveryEmailVerified,
          DateTime? createdAt,
          DateTime? updatedAt,
          int? updateCounter,
          bool? isDeleted,
          Value<String?> lastModifiedBy = const Value.absent()}) =>
      School(
        localId: localId ?? this.localId,
        serverId: serverId.present ? serverId.value : this.serverId,
        schoolName: schoolName ?? this.schoolName,
        shortCode: shortCode ?? this.shortCode,
        logoUrl: logoUrl.present ? logoUrl.value : this.logoUrl,
        subscriptionTier: subscriptionTier ?? this.subscriptionTier,
        activeCurriculum: activeCurriculum ?? this.activeCurriculum,
        activeCurriculumVersion: activeCurriculumVersion.present
            ? activeCurriculumVersion.value
            : this.activeCurriculumVersion,
        totalSeats: totalSeats ?? this.totalSeats,
        schoolMasterKeyWrapped: schoolMasterKeyWrapped.present
            ? schoolMasterKeyWrapped.value
            : this.schoolMasterKeyWrapped,
        adminRecoveryEmail: adminRecoveryEmail.present
            ? adminRecoveryEmail.value
            : this.adminRecoveryEmail,
        adminRecoveryEmailVerified:
            adminRecoveryEmailVerified ?? this.adminRecoveryEmailVerified,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        updateCounter: updateCounter ?? this.updateCounter,
        isDeleted: isDeleted ?? this.isDeleted,
        lastModifiedBy:
            lastModifiedBy.present ? lastModifiedBy.value : this.lastModifiedBy,
      );
  School copyWithCompanion(SchoolsCompanion data) {
    return School(
      localId: data.localId.present ? data.localId.value : this.localId,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      schoolName:
          data.schoolName.present ? data.schoolName.value : this.schoolName,
      shortCode: data.shortCode.present ? data.shortCode.value : this.shortCode,
      logoUrl: data.logoUrl.present ? data.logoUrl.value : this.logoUrl,
      subscriptionTier: data.subscriptionTier.present
          ? data.subscriptionTier.value
          : this.subscriptionTier,
      activeCurriculum: data.activeCurriculum.present
          ? data.activeCurriculum.value
          : this.activeCurriculum,
      activeCurriculumVersion: data.activeCurriculumVersion.present
          ? data.activeCurriculumVersion.value
          : this.activeCurriculumVersion,
      totalSeats:
          data.totalSeats.present ? data.totalSeats.value : this.totalSeats,
      schoolMasterKeyWrapped: data.schoolMasterKeyWrapped.present
          ? data.schoolMasterKeyWrapped.value
          : this.schoolMasterKeyWrapped,
      adminRecoveryEmail: data.adminRecoveryEmail.present
          ? data.adminRecoveryEmail.value
          : this.adminRecoveryEmail,
      adminRecoveryEmailVerified: data.adminRecoveryEmailVerified.present
          ? data.adminRecoveryEmailVerified.value
          : this.adminRecoveryEmailVerified,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updateCounter: data.updateCounter.present
          ? data.updateCounter.value
          : this.updateCounter,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      lastModifiedBy: data.lastModifiedBy.present
          ? data.lastModifiedBy.value
          : this.lastModifiedBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('School(')
          ..write('localId: $localId, ')
          ..write('serverId: $serverId, ')
          ..write('schoolName: $schoolName, ')
          ..write('shortCode: $shortCode, ')
          ..write('logoUrl: $logoUrl, ')
          ..write('subscriptionTier: $subscriptionTier, ')
          ..write('activeCurriculum: $activeCurriculum, ')
          ..write('activeCurriculumVersion: $activeCurriculumVersion, ')
          ..write('totalSeats: $totalSeats, ')
          ..write('schoolMasterKeyWrapped: $schoolMasterKeyWrapped, ')
          ..write('adminRecoveryEmail: $adminRecoveryEmail, ')
          ..write('adminRecoveryEmailVerified: $adminRecoveryEmailVerified, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updateCounter: $updateCounter, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('lastModifiedBy: $lastModifiedBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      localId,
      serverId,
      schoolName,
      shortCode,
      logoUrl,
      subscriptionTier,
      activeCurriculum,
      activeCurriculumVersion,
      totalSeats,
      schoolMasterKeyWrapped,
      adminRecoveryEmail,
      adminRecoveryEmailVerified,
      createdAt,
      updatedAt,
      updateCounter,
      isDeleted,
      lastModifiedBy);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is School &&
          other.localId == this.localId &&
          other.serverId == this.serverId &&
          other.schoolName == this.schoolName &&
          other.shortCode == this.shortCode &&
          other.logoUrl == this.logoUrl &&
          other.subscriptionTier == this.subscriptionTier &&
          other.activeCurriculum == this.activeCurriculum &&
          other.activeCurriculumVersion == this.activeCurriculumVersion &&
          other.totalSeats == this.totalSeats &&
          other.schoolMasterKeyWrapped == this.schoolMasterKeyWrapped &&
          other.adminRecoveryEmail == this.adminRecoveryEmail &&
          other.adminRecoveryEmailVerified == this.adminRecoveryEmailVerified &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.updateCounter == this.updateCounter &&
          other.isDeleted == this.isDeleted &&
          other.lastModifiedBy == this.lastModifiedBy);
}

class SchoolsCompanion extends UpdateCompanion<School> {
  final Value<int> localId;
  final Value<String?> serverId;
  final Value<String> schoolName;
  final Value<String> shortCode;
  final Value<String?> logoUrl;
  final Value<String> subscriptionTier;
  final Value<String> activeCurriculum;
  final Value<String?> activeCurriculumVersion;
  final Value<int> totalSeats;
  final Value<String?> schoolMasterKeyWrapped;
  final Value<String?> adminRecoveryEmail;
  final Value<bool> adminRecoveryEmailVerified;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> updateCounter;
  final Value<bool> isDeleted;
  final Value<String?> lastModifiedBy;
  const SchoolsCompanion({
    this.localId = const Value.absent(),
    this.serverId = const Value.absent(),
    this.schoolName = const Value.absent(),
    this.shortCode = const Value.absent(),
    this.logoUrl = const Value.absent(),
    this.subscriptionTier = const Value.absent(),
    this.activeCurriculum = const Value.absent(),
    this.activeCurriculumVersion = const Value.absent(),
    this.totalSeats = const Value.absent(),
    this.schoolMasterKeyWrapped = const Value.absent(),
    this.adminRecoveryEmail = const Value.absent(),
    this.adminRecoveryEmailVerified = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updateCounter = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.lastModifiedBy = const Value.absent(),
  });
  SchoolsCompanion.insert({
    this.localId = const Value.absent(),
    this.serverId = const Value.absent(),
    required String schoolName,
    required String shortCode,
    this.logoUrl = const Value.absent(),
    this.subscriptionTier = const Value.absent(),
    this.activeCurriculum = const Value.absent(),
    this.activeCurriculumVersion = const Value.absent(),
    this.totalSeats = const Value.absent(),
    this.schoolMasterKeyWrapped = const Value.absent(),
    this.adminRecoveryEmail = const Value.absent(),
    this.adminRecoveryEmailVerified = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updateCounter = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.lastModifiedBy = const Value.absent(),
  })  : schoolName = Value(schoolName),
        shortCode = Value(shortCode);
  static Insertable<School> custom({
    Expression<int>? localId,
    Expression<String>? serverId,
    Expression<String>? schoolName,
    Expression<String>? shortCode,
    Expression<String>? logoUrl,
    Expression<String>? subscriptionTier,
    Expression<String>? activeCurriculum,
    Expression<String>? activeCurriculumVersion,
    Expression<int>? totalSeats,
    Expression<String>? schoolMasterKeyWrapped,
    Expression<String>? adminRecoveryEmail,
    Expression<bool>? adminRecoveryEmailVerified,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? updateCounter,
    Expression<bool>? isDeleted,
    Expression<String>? lastModifiedBy,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (serverId != null) 'server_id': serverId,
      if (schoolName != null) 'school_name': schoolName,
      if (shortCode != null) 'short_code': shortCode,
      if (logoUrl != null) 'logo_url': logoUrl,
      if (subscriptionTier != null) 'subscription_tier': subscriptionTier,
      if (activeCurriculum != null) 'active_curriculum': activeCurriculum,
      if (activeCurriculumVersion != null)
        'active_curriculum_version': activeCurriculumVersion,
      if (totalSeats != null) 'total_seats': totalSeats,
      if (schoolMasterKeyWrapped != null)
        'school_master_key_wrapped': schoolMasterKeyWrapped,
      if (adminRecoveryEmail != null)
        'admin_recovery_email': adminRecoveryEmail,
      if (adminRecoveryEmailVerified != null)
        'admin_recovery_email_verified': adminRecoveryEmailVerified,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updateCounter != null) 'update_counter': updateCounter,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (lastModifiedBy != null) 'last_modified_by': lastModifiedBy,
    });
  }

  SchoolsCompanion copyWith(
      {Value<int>? localId,
      Value<String?>? serverId,
      Value<String>? schoolName,
      Value<String>? shortCode,
      Value<String?>? logoUrl,
      Value<String>? subscriptionTier,
      Value<String>? activeCurriculum,
      Value<String?>? activeCurriculumVersion,
      Value<int>? totalSeats,
      Value<String?>? schoolMasterKeyWrapped,
      Value<String?>? adminRecoveryEmail,
      Value<bool>? adminRecoveryEmailVerified,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? updateCounter,
      Value<bool>? isDeleted,
      Value<String?>? lastModifiedBy}) {
    return SchoolsCompanion(
      localId: localId ?? this.localId,
      serverId: serverId ?? this.serverId,
      schoolName: schoolName ?? this.schoolName,
      shortCode: shortCode ?? this.shortCode,
      logoUrl: logoUrl ?? this.logoUrl,
      subscriptionTier: subscriptionTier ?? this.subscriptionTier,
      activeCurriculum: activeCurriculum ?? this.activeCurriculum,
      activeCurriculumVersion:
          activeCurriculumVersion ?? this.activeCurriculumVersion,
      totalSeats: totalSeats ?? this.totalSeats,
      schoolMasterKeyWrapped:
          schoolMasterKeyWrapped ?? this.schoolMasterKeyWrapped,
      adminRecoveryEmail: adminRecoveryEmail ?? this.adminRecoveryEmail,
      adminRecoveryEmailVerified:
          adminRecoveryEmailVerified ?? this.adminRecoveryEmailVerified,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updateCounter: updateCounter ?? this.updateCounter,
      isDeleted: isDeleted ?? this.isDeleted,
      lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<int>(localId.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (schoolName.present) {
      map['school_name'] = Variable<String>(schoolName.value);
    }
    if (shortCode.present) {
      map['short_code'] = Variable<String>(shortCode.value);
    }
    if (logoUrl.present) {
      map['logo_url'] = Variable<String>(logoUrl.value);
    }
    if (subscriptionTier.present) {
      map['subscription_tier'] = Variable<String>(subscriptionTier.value);
    }
    if (activeCurriculum.present) {
      map['active_curriculum'] = Variable<String>(activeCurriculum.value);
    }
    if (activeCurriculumVersion.present) {
      map['active_curriculum_version'] =
          Variable<String>(activeCurriculumVersion.value);
    }
    if (totalSeats.present) {
      map['total_seats'] = Variable<int>(totalSeats.value);
    }
    if (schoolMasterKeyWrapped.present) {
      map['school_master_key_wrapped'] =
          Variable<String>(schoolMasterKeyWrapped.value);
    }
    if (adminRecoveryEmail.present) {
      map['admin_recovery_email'] = Variable<String>(adminRecoveryEmail.value);
    }
    if (adminRecoveryEmailVerified.present) {
      map['admin_recovery_email_verified'] =
          Variable<bool>(adminRecoveryEmailVerified.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updateCounter.present) {
      map['update_counter'] = Variable<int>(updateCounter.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (lastModifiedBy.present) {
      map['last_modified_by'] = Variable<String>(lastModifiedBy.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SchoolsCompanion(')
          ..write('localId: $localId, ')
          ..write('serverId: $serverId, ')
          ..write('schoolName: $schoolName, ')
          ..write('shortCode: $shortCode, ')
          ..write('logoUrl: $logoUrl, ')
          ..write('subscriptionTier: $subscriptionTier, ')
          ..write('activeCurriculum: $activeCurriculum, ')
          ..write('activeCurriculumVersion: $activeCurriculumVersion, ')
          ..write('totalSeats: $totalSeats, ')
          ..write('schoolMasterKeyWrapped: $schoolMasterKeyWrapped, ')
          ..write('adminRecoveryEmail: $adminRecoveryEmail, ')
          ..write('adminRecoveryEmailVerified: $adminRecoveryEmailVerified, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updateCounter: $updateCounter, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('lastModifiedBy: $lastModifiedBy')
          ..write(')'))
        .toString();
  }
}

class $TeachersTable extends Teachers with TableInfo<$TeachersTable, Teacher> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TeachersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta =
      const VerificationMeta('localId');
  @override
  late final GeneratedColumn<int> localId = GeneratedColumn<int>(
      'local_id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _serverIdMeta =
      const VerificationMeta('serverId');
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
      'server_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
      'email', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _teacherNameMeta =
      const VerificationMeta('teacherName');
  @override
  late final GeneratedColumn<String> teacherName = GeneratedColumn<String>(
      'teacher_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('teacher'));
  static const VerificationMeta _schoolLocalIdMeta =
      const VerificationMeta('schoolLocalId');
  @override
  late final GeneratedColumn<int> schoolLocalId = GeneratedColumn<int>(
      'school_local_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES schools (local_id)'));
  static const VerificationMeta _schoolServerIdMeta =
      const VerificationMeta('schoolServerId');
  @override
  late final GeneratedColumn<String> schoolServerId = GeneratedColumn<String>(
      'school_server_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _forcePasswordResetMeta =
      const VerificationMeta('forcePasswordReset');
  @override
  late final GeneratedColumn<bool> forcePasswordReset = GeneratedColumn<bool>(
      'force_password_reset', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("force_password_reset" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _passwordHashVersionMeta =
      const VerificationMeta('passwordHashVersion');
  @override
  late final GeneratedColumn<int> passwordHashVersion = GeneratedColumn<int>(
      'password_hash_version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _schoolKeyWrappedMeta =
      const VerificationMeta('schoolKeyWrapped');
  @override
  late final GeneratedColumn<String> schoolKeyWrapped = GeneratedColumn<String>(
      'school_key_wrapped', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastCreditRefillDateMeta =
      const VerificationMeta('lastCreditRefillDate');
  @override
  late final GeneratedColumn<DateTime> lastCreditRefillDate =
      GeneratedColumn<DateTime>('last_credit_refill_date', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updateCounterMeta =
      const VerificationMeta('updateCounter');
  @override
  late final GeneratedColumn<int> updateCounter = GeneratedColumn<int>(
      'update_counter', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isDeletedMeta =
      const VerificationMeta('isDeleted');
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
      'is_deleted', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_deleted" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _saltMeta = const VerificationMeta('salt');
  @override
  late final GeneratedColumn<String> salt = GeneratedColumn<String>(
      'salt', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastModifiedByMeta =
      const VerificationMeta('lastModifiedBy');
  @override
  late final GeneratedColumn<String> lastModifiedBy = GeneratedColumn<String>(
      'last_modified_by', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        localId,
        serverId,
        email,
        teacherName,
        role,
        schoolLocalId,
        schoolServerId,
        isActive,
        forcePasswordReset,
        passwordHashVersion,
        schoolKeyWrapped,
        lastCreditRefillDate,
        createdAt,
        updatedAt,
        updateCounter,
        isDeleted,
        salt,
        lastModifiedBy
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'teachers';
  @override
  VerificationContext validateIntegrity(Insertable<Teacher> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(_localIdMeta,
          localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta));
    }
    if (data.containsKey('server_id')) {
      context.handle(_serverIdMeta,
          serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta));
    }
    if (data.containsKey('email')) {
      context.handle(
          _emailMeta, email.isAcceptableOrUnknown(data['email']!, _emailMeta));
    } else if (isInserting) {
      context.missing(_emailMeta);
    }
    if (data.containsKey('teacher_name')) {
      context.handle(
          _teacherNameMeta,
          teacherName.isAcceptableOrUnknown(
              data['teacher_name']!, _teacherNameMeta));
    } else if (isInserting) {
      context.missing(_teacherNameMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    }
    if (data.containsKey('school_local_id')) {
      context.handle(
          _schoolLocalIdMeta,
          schoolLocalId.isAcceptableOrUnknown(
              data['school_local_id']!, _schoolLocalIdMeta));
    } else if (isInserting) {
      context.missing(_schoolLocalIdMeta);
    }
    if (data.containsKey('school_server_id')) {
      context.handle(
          _schoolServerIdMeta,
          schoolServerId.isAcceptableOrUnknown(
              data['school_server_id']!, _schoolServerIdMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('force_password_reset')) {
      context.handle(
          _forcePasswordResetMeta,
          forcePasswordReset.isAcceptableOrUnknown(
              data['force_password_reset']!, _forcePasswordResetMeta));
    }
    if (data.containsKey('password_hash_version')) {
      context.handle(
          _passwordHashVersionMeta,
          passwordHashVersion.isAcceptableOrUnknown(
              data['password_hash_version']!, _passwordHashVersionMeta));
    }
    if (data.containsKey('school_key_wrapped')) {
      context.handle(
          _schoolKeyWrappedMeta,
          schoolKeyWrapped.isAcceptableOrUnknown(
              data['school_key_wrapped']!, _schoolKeyWrappedMeta));
    }
    if (data.containsKey('last_credit_refill_date')) {
      context.handle(
          _lastCreditRefillDateMeta,
          lastCreditRefillDate.isAcceptableOrUnknown(
              data['last_credit_refill_date']!, _lastCreditRefillDateMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('update_counter')) {
      context.handle(
          _updateCounterMeta,
          updateCounter.isAcceptableOrUnknown(
              data['update_counter']!, _updateCounterMeta));
    }
    if (data.containsKey('is_deleted')) {
      context.handle(_isDeletedMeta,
          isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta));
    }
    if (data.containsKey('salt')) {
      context.handle(
          _saltMeta, salt.isAcceptableOrUnknown(data['salt']!, _saltMeta));
    }
    if (data.containsKey('last_modified_by')) {
      context.handle(
          _lastModifiedByMeta,
          lastModifiedBy.isAcceptableOrUnknown(
              data['last_modified_by']!, _lastModifiedByMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  Teacher map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Teacher(
      localId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}local_id'])!,
      serverId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}server_id']),
      email: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}email'])!,
      teacherName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}teacher_name'])!,
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!,
      schoolLocalId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}school_local_id'])!,
      schoolServerId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}school_server_id']),
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      forcePasswordReset: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}force_password_reset'])!,
      passwordHashVersion: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}password_hash_version'])!,
      schoolKeyWrapped: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}school_key_wrapped']),
      lastCreditRefillDate: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime,
          data['${effectivePrefix}last_credit_refill_date']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      updateCounter: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}update_counter'])!,
      isDeleted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_deleted'])!,
      salt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}salt']),
      lastModifiedBy: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}last_modified_by']),
    );
  }

  @override
  $TeachersTable createAlias(String alias) {
    return $TeachersTable(attachedDatabase, alias);
  }
}

class Teacher extends DataClass implements Insertable<Teacher> {
  final int localId;
  final String? serverId;
  final String email;
  final String teacherName;
  final String role;
  final int schoolLocalId;
  final String? schoolServerId;
  final bool isActive;
  final bool forcePasswordReset;
  final int passwordHashVersion;
  final String? schoolKeyWrapped;
  final DateTime? lastCreditRefillDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int updateCounter;
  final bool isDeleted;
  final String? salt;
  final String? lastModifiedBy;
  const Teacher(
      {required this.localId,
      this.serverId,
      required this.email,
      required this.teacherName,
      required this.role,
      required this.schoolLocalId,
      this.schoolServerId,
      required this.isActive,
      required this.forcePasswordReset,
      required this.passwordHashVersion,
      this.schoolKeyWrapped,
      this.lastCreditRefillDate,
      required this.createdAt,
      required this.updatedAt,
      required this.updateCounter,
      required this.isDeleted,
      this.salt,
      this.lastModifiedBy});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_id'] = Variable<int>(localId);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    map['email'] = Variable<String>(email);
    map['teacher_name'] = Variable<String>(teacherName);
    map['role'] = Variable<String>(role);
    map['school_local_id'] = Variable<int>(schoolLocalId);
    if (!nullToAbsent || schoolServerId != null) {
      map['school_server_id'] = Variable<String>(schoolServerId);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['force_password_reset'] = Variable<bool>(forcePasswordReset);
    map['password_hash_version'] = Variable<int>(passwordHashVersion);
    if (!nullToAbsent || schoolKeyWrapped != null) {
      map['school_key_wrapped'] = Variable<String>(schoolKeyWrapped);
    }
    if (!nullToAbsent || lastCreditRefillDate != null) {
      map['last_credit_refill_date'] = Variable<DateTime>(lastCreditRefillDate);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['update_counter'] = Variable<int>(updateCounter);
    map['is_deleted'] = Variable<bool>(isDeleted);
    if (!nullToAbsent || salt != null) {
      map['salt'] = Variable<String>(salt);
    }
    if (!nullToAbsent || lastModifiedBy != null) {
      map['last_modified_by'] = Variable<String>(lastModifiedBy);
    }
    return map;
  }

  TeachersCompanion toCompanion(bool nullToAbsent) {
    return TeachersCompanion(
      localId: Value(localId),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      email: Value(email),
      teacherName: Value(teacherName),
      role: Value(role),
      schoolLocalId: Value(schoolLocalId),
      schoolServerId: schoolServerId == null && nullToAbsent
          ? const Value.absent()
          : Value(schoolServerId),
      isActive: Value(isActive),
      forcePasswordReset: Value(forcePasswordReset),
      passwordHashVersion: Value(passwordHashVersion),
      schoolKeyWrapped: schoolKeyWrapped == null && nullToAbsent
          ? const Value.absent()
          : Value(schoolKeyWrapped),
      lastCreditRefillDate: lastCreditRefillDate == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCreditRefillDate),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      updateCounter: Value(updateCounter),
      isDeleted: Value(isDeleted),
      salt: salt == null && nullToAbsent ? const Value.absent() : Value(salt),
      lastModifiedBy: lastModifiedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(lastModifiedBy),
    );
  }

  factory Teacher.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Teacher(
      localId: serializer.fromJson<int>(json['localId']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      email: serializer.fromJson<String>(json['email']),
      teacherName: serializer.fromJson<String>(json['teacherName']),
      role: serializer.fromJson<String>(json['role']),
      schoolLocalId: serializer.fromJson<int>(json['schoolLocalId']),
      schoolServerId: serializer.fromJson<String?>(json['schoolServerId']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      forcePasswordReset: serializer.fromJson<bool>(json['forcePasswordReset']),
      passwordHashVersion:
          serializer.fromJson<int>(json['passwordHashVersion']),
      schoolKeyWrapped: serializer.fromJson<String?>(json['schoolKeyWrapped']),
      lastCreditRefillDate:
          serializer.fromJson<DateTime?>(json['lastCreditRefillDate']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updateCounter: serializer.fromJson<int>(json['updateCounter']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      salt: serializer.fromJson<String?>(json['salt']),
      lastModifiedBy: serializer.fromJson<String?>(json['lastModifiedBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localId': serializer.toJson<int>(localId),
      'serverId': serializer.toJson<String?>(serverId),
      'email': serializer.toJson<String>(email),
      'teacherName': serializer.toJson<String>(teacherName),
      'role': serializer.toJson<String>(role),
      'schoolLocalId': serializer.toJson<int>(schoolLocalId),
      'schoolServerId': serializer.toJson<String?>(schoolServerId),
      'isActive': serializer.toJson<bool>(isActive),
      'forcePasswordReset': serializer.toJson<bool>(forcePasswordReset),
      'passwordHashVersion': serializer.toJson<int>(passwordHashVersion),
      'schoolKeyWrapped': serializer.toJson<String?>(schoolKeyWrapped),
      'lastCreditRefillDate':
          serializer.toJson<DateTime?>(lastCreditRefillDate),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updateCounter': serializer.toJson<int>(updateCounter),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'salt': serializer.toJson<String?>(salt),
      'lastModifiedBy': serializer.toJson<String?>(lastModifiedBy),
    };
  }

  Teacher copyWith(
          {int? localId,
          Value<String?> serverId = const Value.absent(),
          String? email,
          String? teacherName,
          String? role,
          int? schoolLocalId,
          Value<String?> schoolServerId = const Value.absent(),
          bool? isActive,
          bool? forcePasswordReset,
          int? passwordHashVersion,
          Value<String?> schoolKeyWrapped = const Value.absent(),
          Value<DateTime?> lastCreditRefillDate = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt,
          int? updateCounter,
          bool? isDeleted,
          Value<String?> salt = const Value.absent(),
          Value<String?> lastModifiedBy = const Value.absent()}) =>
      Teacher(
        localId: localId ?? this.localId,
        serverId: serverId.present ? serverId.value : this.serverId,
        email: email ?? this.email,
        teacherName: teacherName ?? this.teacherName,
        role: role ?? this.role,
        schoolLocalId: schoolLocalId ?? this.schoolLocalId,
        schoolServerId:
            schoolServerId.present ? schoolServerId.value : this.schoolServerId,
        isActive: isActive ?? this.isActive,
        forcePasswordReset: forcePasswordReset ?? this.forcePasswordReset,
        passwordHashVersion: passwordHashVersion ?? this.passwordHashVersion,
        schoolKeyWrapped: schoolKeyWrapped.present
            ? schoolKeyWrapped.value
            : this.schoolKeyWrapped,
        lastCreditRefillDate: lastCreditRefillDate.present
            ? lastCreditRefillDate.value
            : this.lastCreditRefillDate,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        updateCounter: updateCounter ?? this.updateCounter,
        isDeleted: isDeleted ?? this.isDeleted,
        salt: salt.present ? salt.value : this.salt,
        lastModifiedBy:
            lastModifiedBy.present ? lastModifiedBy.value : this.lastModifiedBy,
      );
  Teacher copyWithCompanion(TeachersCompanion data) {
    return Teacher(
      localId: data.localId.present ? data.localId.value : this.localId,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      email: data.email.present ? data.email.value : this.email,
      teacherName:
          data.teacherName.present ? data.teacherName.value : this.teacherName,
      role: data.role.present ? data.role.value : this.role,
      schoolLocalId: data.schoolLocalId.present
          ? data.schoolLocalId.value
          : this.schoolLocalId,
      schoolServerId: data.schoolServerId.present
          ? data.schoolServerId.value
          : this.schoolServerId,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      forcePasswordReset: data.forcePasswordReset.present
          ? data.forcePasswordReset.value
          : this.forcePasswordReset,
      passwordHashVersion: data.passwordHashVersion.present
          ? data.passwordHashVersion.value
          : this.passwordHashVersion,
      schoolKeyWrapped: data.schoolKeyWrapped.present
          ? data.schoolKeyWrapped.value
          : this.schoolKeyWrapped,
      lastCreditRefillDate: data.lastCreditRefillDate.present
          ? data.lastCreditRefillDate.value
          : this.lastCreditRefillDate,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updateCounter: data.updateCounter.present
          ? data.updateCounter.value
          : this.updateCounter,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      salt: data.salt.present ? data.salt.value : this.salt,
      lastModifiedBy: data.lastModifiedBy.present
          ? data.lastModifiedBy.value
          : this.lastModifiedBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Teacher(')
          ..write('localId: $localId, ')
          ..write('serverId: $serverId, ')
          ..write('email: $email, ')
          ..write('teacherName: $teacherName, ')
          ..write('role: $role, ')
          ..write('schoolLocalId: $schoolLocalId, ')
          ..write('schoolServerId: $schoolServerId, ')
          ..write('isActive: $isActive, ')
          ..write('forcePasswordReset: $forcePasswordReset, ')
          ..write('passwordHashVersion: $passwordHashVersion, ')
          ..write('schoolKeyWrapped: $schoolKeyWrapped, ')
          ..write('lastCreditRefillDate: $lastCreditRefillDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updateCounter: $updateCounter, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('salt: $salt, ')
          ..write('lastModifiedBy: $lastModifiedBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      localId,
      serverId,
      email,
      teacherName,
      role,
      schoolLocalId,
      schoolServerId,
      isActive,
      forcePasswordReset,
      passwordHashVersion,
      schoolKeyWrapped,
      lastCreditRefillDate,
      createdAt,
      updatedAt,
      updateCounter,
      isDeleted,
      salt,
      lastModifiedBy);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Teacher &&
          other.localId == this.localId &&
          other.serverId == this.serverId &&
          other.email == this.email &&
          other.teacherName == this.teacherName &&
          other.role == this.role &&
          other.schoolLocalId == this.schoolLocalId &&
          other.schoolServerId == this.schoolServerId &&
          other.isActive == this.isActive &&
          other.forcePasswordReset == this.forcePasswordReset &&
          other.passwordHashVersion == this.passwordHashVersion &&
          other.schoolKeyWrapped == this.schoolKeyWrapped &&
          other.lastCreditRefillDate == this.lastCreditRefillDate &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.updateCounter == this.updateCounter &&
          other.isDeleted == this.isDeleted &&
          other.salt == this.salt &&
          other.lastModifiedBy == this.lastModifiedBy);
}

class TeachersCompanion extends UpdateCompanion<Teacher> {
  final Value<int> localId;
  final Value<String?> serverId;
  final Value<String> email;
  final Value<String> teacherName;
  final Value<String> role;
  final Value<int> schoolLocalId;
  final Value<String?> schoolServerId;
  final Value<bool> isActive;
  final Value<bool> forcePasswordReset;
  final Value<int> passwordHashVersion;
  final Value<String?> schoolKeyWrapped;
  final Value<DateTime?> lastCreditRefillDate;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> updateCounter;
  final Value<bool> isDeleted;
  final Value<String?> salt;
  final Value<String?> lastModifiedBy;
  const TeachersCompanion({
    this.localId = const Value.absent(),
    this.serverId = const Value.absent(),
    this.email = const Value.absent(),
    this.teacherName = const Value.absent(),
    this.role = const Value.absent(),
    this.schoolLocalId = const Value.absent(),
    this.schoolServerId = const Value.absent(),
    this.isActive = const Value.absent(),
    this.forcePasswordReset = const Value.absent(),
    this.passwordHashVersion = const Value.absent(),
    this.schoolKeyWrapped = const Value.absent(),
    this.lastCreditRefillDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updateCounter = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.salt = const Value.absent(),
    this.lastModifiedBy = const Value.absent(),
  });
  TeachersCompanion.insert({
    this.localId = const Value.absent(),
    this.serverId = const Value.absent(),
    required String email,
    required String teacherName,
    this.role = const Value.absent(),
    required int schoolLocalId,
    this.schoolServerId = const Value.absent(),
    this.isActive = const Value.absent(),
    this.forcePasswordReset = const Value.absent(),
    this.passwordHashVersion = const Value.absent(),
    this.schoolKeyWrapped = const Value.absent(),
    this.lastCreditRefillDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updateCounter = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.salt = const Value.absent(),
    this.lastModifiedBy = const Value.absent(),
  })  : email = Value(email),
        teacherName = Value(teacherName),
        schoolLocalId = Value(schoolLocalId);
  static Insertable<Teacher> custom({
    Expression<int>? localId,
    Expression<String>? serverId,
    Expression<String>? email,
    Expression<String>? teacherName,
    Expression<String>? role,
    Expression<int>? schoolLocalId,
    Expression<String>? schoolServerId,
    Expression<bool>? isActive,
    Expression<bool>? forcePasswordReset,
    Expression<int>? passwordHashVersion,
    Expression<String>? schoolKeyWrapped,
    Expression<DateTime>? lastCreditRefillDate,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? updateCounter,
    Expression<bool>? isDeleted,
    Expression<String>? salt,
    Expression<String>? lastModifiedBy,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (serverId != null) 'server_id': serverId,
      if (email != null) 'email': email,
      if (teacherName != null) 'teacher_name': teacherName,
      if (role != null) 'role': role,
      if (schoolLocalId != null) 'school_local_id': schoolLocalId,
      if (schoolServerId != null) 'school_server_id': schoolServerId,
      if (isActive != null) 'is_active': isActive,
      if (forcePasswordReset != null)
        'force_password_reset': forcePasswordReset,
      if (passwordHashVersion != null)
        'password_hash_version': passwordHashVersion,
      if (schoolKeyWrapped != null) 'school_key_wrapped': schoolKeyWrapped,
      if (lastCreditRefillDate != null)
        'last_credit_refill_date': lastCreditRefillDate,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updateCounter != null) 'update_counter': updateCounter,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (salt != null) 'salt': salt,
      if (lastModifiedBy != null) 'last_modified_by': lastModifiedBy,
    });
  }

  TeachersCompanion copyWith(
      {Value<int>? localId,
      Value<String?>? serverId,
      Value<String>? email,
      Value<String>? teacherName,
      Value<String>? role,
      Value<int>? schoolLocalId,
      Value<String?>? schoolServerId,
      Value<bool>? isActive,
      Value<bool>? forcePasswordReset,
      Value<int>? passwordHashVersion,
      Value<String?>? schoolKeyWrapped,
      Value<DateTime?>? lastCreditRefillDate,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? updateCounter,
      Value<bool>? isDeleted,
      Value<String?>? salt,
      Value<String?>? lastModifiedBy}) {
    return TeachersCompanion(
      localId: localId ?? this.localId,
      serverId: serverId ?? this.serverId,
      email: email ?? this.email,
      teacherName: teacherName ?? this.teacherName,
      role: role ?? this.role,
      schoolLocalId: schoolLocalId ?? this.schoolLocalId,
      schoolServerId: schoolServerId ?? this.schoolServerId,
      isActive: isActive ?? this.isActive,
      forcePasswordReset: forcePasswordReset ?? this.forcePasswordReset,
      passwordHashVersion: passwordHashVersion ?? this.passwordHashVersion,
      schoolKeyWrapped: schoolKeyWrapped ?? this.schoolKeyWrapped,
      lastCreditRefillDate: lastCreditRefillDate ?? this.lastCreditRefillDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updateCounter: updateCounter ?? this.updateCounter,
      isDeleted: isDeleted ?? this.isDeleted,
      salt: salt ?? this.salt,
      lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<int>(localId.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (teacherName.present) {
      map['teacher_name'] = Variable<String>(teacherName.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (schoolLocalId.present) {
      map['school_local_id'] = Variable<int>(schoolLocalId.value);
    }
    if (schoolServerId.present) {
      map['school_server_id'] = Variable<String>(schoolServerId.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (forcePasswordReset.present) {
      map['force_password_reset'] = Variable<bool>(forcePasswordReset.value);
    }
    if (passwordHashVersion.present) {
      map['password_hash_version'] = Variable<int>(passwordHashVersion.value);
    }
    if (schoolKeyWrapped.present) {
      map['school_key_wrapped'] = Variable<String>(schoolKeyWrapped.value);
    }
    if (lastCreditRefillDate.present) {
      map['last_credit_refill_date'] =
          Variable<DateTime>(lastCreditRefillDate.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updateCounter.present) {
      map['update_counter'] = Variable<int>(updateCounter.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (salt.present) {
      map['salt'] = Variable<String>(salt.value);
    }
    if (lastModifiedBy.present) {
      map['last_modified_by'] = Variable<String>(lastModifiedBy.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TeachersCompanion(')
          ..write('localId: $localId, ')
          ..write('serverId: $serverId, ')
          ..write('email: $email, ')
          ..write('teacherName: $teacherName, ')
          ..write('role: $role, ')
          ..write('schoolLocalId: $schoolLocalId, ')
          ..write('schoolServerId: $schoolServerId, ')
          ..write('isActive: $isActive, ')
          ..write('forcePasswordReset: $forcePasswordReset, ')
          ..write('passwordHashVersion: $passwordHashVersion, ')
          ..write('schoolKeyWrapped: $schoolKeyWrapped, ')
          ..write('lastCreditRefillDate: $lastCreditRefillDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updateCounter: $updateCounter, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('salt: $salt, ')
          ..write('lastModifiedBy: $lastModifiedBy')
          ..write(')'))
        .toString();
  }
}

class $SubjectsTable extends Subjects with TableInfo<$SubjectsTable, Subject> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SubjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  @override
  List<GeneratedColumn> get $columns => [id];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'subjects';
  @override
  VerificationContext validateIntegrity(Insertable<Subject> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Subject map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Subject(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
    );
  }

  @override
  $SubjectsTable createAlias(String alias) {
    return $SubjectsTable(attachedDatabase, alias);
  }
}

class Subject extends DataClass implements Insertable<Subject> {
  final int id;
  const Subject({required this.id});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    return map;
  }

  SubjectsCompanion toCompanion(bool nullToAbsent) {
    return SubjectsCompanion(
      id: Value(id),
    );
  }

  factory Subject.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Subject(
      id: serializer.fromJson<int>(json['id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
    };
  }

  Subject copyWith({int? id}) => Subject(
        id: id ?? this.id,
      );
  Subject copyWithCompanion(SubjectsCompanion data) {
    return Subject(
      id: data.id.present ? data.id.value : this.id,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Subject(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => id.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Subject && other.id == this.id);
}

class SubjectsCompanion extends UpdateCompanion<Subject> {
  final Value<int> id;
  const SubjectsCompanion({
    this.id = const Value.absent(),
  });
  SubjectsCompanion.insert({
    this.id = const Value.absent(),
  });
  static Insertable<Subject> custom({
    Expression<int>? id,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
    });
  }

  SubjectsCompanion copyWith({Value<int>? id}) {
    return SubjectsCompanion(
      id: id ?? this.id,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SubjectsCompanion(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }
}

class $LessonsTable extends Lessons with TableInfo<$LessonsTable, Lesson> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LessonsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _subjectMeta =
      const VerificationMeta('subject');
  @override
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
      'subject', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _classLevelMeta =
      const VerificationMeta('classLevel');
  @override
  late final GeneratedColumn<String> classLevel = GeneratedColumn<String>(
      'class_level', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _weekMeta = const VerificationMeta('week');
  @override
  late final GeneratedColumn<int> week = GeneratedColumn<int>(
      'week', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _topicMeta = const VerificationMeta('topic');
  @override
  late final GeneratedColumn<String> topic = GeneratedColumn<String>(
      'topic', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _difficultyMeta =
      const VerificationMeta('difficulty');
  @override
  late final GeneratedColumn<String> difficulty = GeneratedColumn<String>(
      'difficulty', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _bloomsVerbsMeta =
      const VerificationMeta('bloomsVerbs');
  @override
  late final GeneratedColumn<String> bloomsVerbs = GeneratedColumn<String>(
      'blooms_verbs', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _curriculumMeta =
      const VerificationMeta('curriculum');
  @override
  late final GeneratedColumn<String> curriculum = GeneratedColumn<String>(
      'curriculum', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        subject,
        classLevel,
        week,
        topic,
        difficulty,
        bloomsVerbs,
        curriculum,
        content,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lessons';
  @override
  VerificationContext validateIntegrity(Insertable<Lesson> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('subject')) {
      context.handle(_subjectMeta,
          subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta));
    } else if (isInserting) {
      context.missing(_subjectMeta);
    }
    if (data.containsKey('class_level')) {
      context.handle(
          _classLevelMeta,
          classLevel.isAcceptableOrUnknown(
              data['class_level']!, _classLevelMeta));
    } else if (isInserting) {
      context.missing(_classLevelMeta);
    }
    if (data.containsKey('week')) {
      context.handle(
          _weekMeta, week.isAcceptableOrUnknown(data['week']!, _weekMeta));
    } else if (isInserting) {
      context.missing(_weekMeta);
    }
    if (data.containsKey('topic')) {
      context.handle(
          _topicMeta, topic.isAcceptableOrUnknown(data['topic']!, _topicMeta));
    } else if (isInserting) {
      context.missing(_topicMeta);
    }
    if (data.containsKey('difficulty')) {
      context.handle(
          _difficultyMeta,
          difficulty.isAcceptableOrUnknown(
              data['difficulty']!, _difficultyMeta));
    } else if (isInserting) {
      context.missing(_difficultyMeta);
    }
    if (data.containsKey('blooms_verbs')) {
      context.handle(
          _bloomsVerbsMeta,
          bloomsVerbs.isAcceptableOrUnknown(
              data['blooms_verbs']!, _bloomsVerbsMeta));
    } else if (isInserting) {
      context.missing(_bloomsVerbsMeta);
    }
    if (data.containsKey('curriculum')) {
      context.handle(
          _curriculumMeta,
          curriculum.isAcceptableOrUnknown(
              data['curriculum']!, _curriculumMeta));
    } else if (isInserting) {
      context.missing(_curriculumMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Lesson map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Lesson(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      subject: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}subject'])!,
      classLevel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}class_level'])!,
      week: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}week'])!,
      topic: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}topic'])!,
      difficulty: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}difficulty'])!,
      bloomsVerbs: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}blooms_verbs'])!,
      curriculum: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}curriculum'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $LessonsTable createAlias(String alias) {
    return $LessonsTable(attachedDatabase, alias);
  }
}

class Lesson extends DataClass implements Insertable<Lesson> {
  final int id;
  final String subject;
  final String classLevel;
  final int week;
  final String topic;
  final String difficulty;
  final String bloomsVerbs;
  final String curriculum;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Lesson(
      {required this.id,
      required this.subject,
      required this.classLevel,
      required this.week,
      required this.topic,
      required this.difficulty,
      required this.bloomsVerbs,
      required this.curriculum,
      required this.content,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['subject'] = Variable<String>(subject);
    map['class_level'] = Variable<String>(classLevel);
    map['week'] = Variable<int>(week);
    map['topic'] = Variable<String>(topic);
    map['difficulty'] = Variable<String>(difficulty);
    map['blooms_verbs'] = Variable<String>(bloomsVerbs);
    map['curriculum'] = Variable<String>(curriculum);
    map['content'] = Variable<String>(content);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LessonsCompanion toCompanion(bool nullToAbsent) {
    return LessonsCompanion(
      id: Value(id),
      subject: Value(subject),
      classLevel: Value(classLevel),
      week: Value(week),
      topic: Value(topic),
      difficulty: Value(difficulty),
      bloomsVerbs: Value(bloomsVerbs),
      curriculum: Value(curriculum),
      content: Value(content),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Lesson.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Lesson(
      id: serializer.fromJson<int>(json['id']),
      subject: serializer.fromJson<String>(json['subject']),
      classLevel: serializer.fromJson<String>(json['classLevel']),
      week: serializer.fromJson<int>(json['week']),
      topic: serializer.fromJson<String>(json['topic']),
      difficulty: serializer.fromJson<String>(json['difficulty']),
      bloomsVerbs: serializer.fromJson<String>(json['bloomsVerbs']),
      curriculum: serializer.fromJson<String>(json['curriculum']),
      content: serializer.fromJson<String>(json['content']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'subject': serializer.toJson<String>(subject),
      'classLevel': serializer.toJson<String>(classLevel),
      'week': serializer.toJson<int>(week),
      'topic': serializer.toJson<String>(topic),
      'difficulty': serializer.toJson<String>(difficulty),
      'bloomsVerbs': serializer.toJson<String>(bloomsVerbs),
      'curriculum': serializer.toJson<String>(curriculum),
      'content': serializer.toJson<String>(content),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Lesson copyWith(
          {int? id,
          String? subject,
          String? classLevel,
          int? week,
          String? topic,
          String? difficulty,
          String? bloomsVerbs,
          String? curriculum,
          String? content,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Lesson(
        id: id ?? this.id,
        subject: subject ?? this.subject,
        classLevel: classLevel ?? this.classLevel,
        week: week ?? this.week,
        topic: topic ?? this.topic,
        difficulty: difficulty ?? this.difficulty,
        bloomsVerbs: bloomsVerbs ?? this.bloomsVerbs,
        curriculum: curriculum ?? this.curriculum,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Lesson copyWithCompanion(LessonsCompanion data) {
    return Lesson(
      id: data.id.present ? data.id.value : this.id,
      subject: data.subject.present ? data.subject.value : this.subject,
      classLevel:
          data.classLevel.present ? data.classLevel.value : this.classLevel,
      week: data.week.present ? data.week.value : this.week,
      topic: data.topic.present ? data.topic.value : this.topic,
      difficulty:
          data.difficulty.present ? data.difficulty.value : this.difficulty,
      bloomsVerbs:
          data.bloomsVerbs.present ? data.bloomsVerbs.value : this.bloomsVerbs,
      curriculum:
          data.curriculum.present ? data.curriculum.value : this.curriculum,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Lesson(')
          ..write('id: $id, ')
          ..write('subject: $subject, ')
          ..write('classLevel: $classLevel, ')
          ..write('week: $week, ')
          ..write('topic: $topic, ')
          ..write('difficulty: $difficulty, ')
          ..write('bloomsVerbs: $bloomsVerbs, ')
          ..write('curriculum: $curriculum, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, subject, classLevel, week, topic,
      difficulty, bloomsVerbs, curriculum, content, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Lesson &&
          other.id == this.id &&
          other.subject == this.subject &&
          other.classLevel == this.classLevel &&
          other.week == this.week &&
          other.topic == this.topic &&
          other.difficulty == this.difficulty &&
          other.bloomsVerbs == this.bloomsVerbs &&
          other.curriculum == this.curriculum &&
          other.content == this.content &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class LessonsCompanion extends UpdateCompanion<Lesson> {
  final Value<int> id;
  final Value<String> subject;
  final Value<String> classLevel;
  final Value<int> week;
  final Value<String> topic;
  final Value<String> difficulty;
  final Value<String> bloomsVerbs;
  final Value<String> curriculum;
  final Value<String> content;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const LessonsCompanion({
    this.id = const Value.absent(),
    this.subject = const Value.absent(),
    this.classLevel = const Value.absent(),
    this.week = const Value.absent(),
    this.topic = const Value.absent(),
    this.difficulty = const Value.absent(),
    this.bloomsVerbs = const Value.absent(),
    this.curriculum = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  LessonsCompanion.insert({
    this.id = const Value.absent(),
    required String subject,
    required String classLevel,
    required int week,
    required String topic,
    required String difficulty,
    required String bloomsVerbs,
    required String curriculum,
    required String content,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  })  : subject = Value(subject),
        classLevel = Value(classLevel),
        week = Value(week),
        topic = Value(topic),
        difficulty = Value(difficulty),
        bloomsVerbs = Value(bloomsVerbs),
        curriculum = Value(curriculum),
        content = Value(content);
  static Insertable<Lesson> custom({
    Expression<int>? id,
    Expression<String>? subject,
    Expression<String>? classLevel,
    Expression<int>? week,
    Expression<String>? topic,
    Expression<String>? difficulty,
    Expression<String>? bloomsVerbs,
    Expression<String>? curriculum,
    Expression<String>? content,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (subject != null) 'subject': subject,
      if (classLevel != null) 'class_level': classLevel,
      if (week != null) 'week': week,
      if (topic != null) 'topic': topic,
      if (difficulty != null) 'difficulty': difficulty,
      if (bloomsVerbs != null) 'blooms_verbs': bloomsVerbs,
      if (curriculum != null) 'curriculum': curriculum,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  LessonsCompanion copyWith(
      {Value<int>? id,
      Value<String>? subject,
      Value<String>? classLevel,
      Value<int>? week,
      Value<String>? topic,
      Value<String>? difficulty,
      Value<String>? bloomsVerbs,
      Value<String>? curriculum,
      Value<String>? content,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt}) {
    return LessonsCompanion(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      classLevel: classLevel ?? this.classLevel,
      week: week ?? this.week,
      topic: topic ?? this.topic,
      difficulty: difficulty ?? this.difficulty,
      bloomsVerbs: bloomsVerbs ?? this.bloomsVerbs,
      curriculum: curriculum ?? this.curriculum,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (classLevel.present) {
      map['class_level'] = Variable<String>(classLevel.value);
    }
    if (week.present) {
      map['week'] = Variable<int>(week.value);
    }
    if (topic.present) {
      map['topic'] = Variable<String>(topic.value);
    }
    if (difficulty.present) {
      map['difficulty'] = Variable<String>(difficulty.value);
    }
    if (bloomsVerbs.present) {
      map['blooms_verbs'] = Variable<String>(bloomsVerbs.value);
    }
    if (curriculum.present) {
      map['curriculum'] = Variable<String>(curriculum.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LessonsCompanion(')
          ..write('id: $id, ')
          ..write('subject: $subject, ')
          ..write('classLevel: $classLevel, ')
          ..write('week: $week, ')
          ..write('topic: $topic, ')
          ..write('difficulty: $difficulty, ')
          ..write('bloomsVerbs: $bloomsVerbs, ')
          ..write('curriculum: $curriculum, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $SchemeOfWorkTable extends SchemeOfWork
    with TableInfo<$SchemeOfWorkTable, SchemeOfWorkData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SchemeOfWorkTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  @override
  List<GeneratedColumn> get $columns => [id];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scheme_of_work';
  @override
  VerificationContext validateIntegrity(Insertable<SchemeOfWorkData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SchemeOfWorkData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SchemeOfWorkData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
    );
  }

  @override
  $SchemeOfWorkTable createAlias(String alias) {
    return $SchemeOfWorkTable(attachedDatabase, alias);
  }
}

class SchemeOfWorkData extends DataClass
    implements Insertable<SchemeOfWorkData> {
  final int id;
  const SchemeOfWorkData({required this.id});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    return map;
  }

  SchemeOfWorkCompanion toCompanion(bool nullToAbsent) {
    return SchemeOfWorkCompanion(
      id: Value(id),
    );
  }

  factory SchemeOfWorkData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SchemeOfWorkData(
      id: serializer.fromJson<int>(json['id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
    };
  }

  SchemeOfWorkData copyWith({int? id}) => SchemeOfWorkData(
        id: id ?? this.id,
      );
  SchemeOfWorkData copyWithCompanion(SchemeOfWorkCompanion data) {
    return SchemeOfWorkData(
      id: data.id.present ? data.id.value : this.id,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SchemeOfWorkData(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => id.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SchemeOfWorkData && other.id == this.id);
}

class SchemeOfWorkCompanion extends UpdateCompanion<SchemeOfWorkData> {
  final Value<int> id;
  const SchemeOfWorkCompanion({
    this.id = const Value.absent(),
  });
  SchemeOfWorkCompanion.insert({
    this.id = const Value.absent(),
  });
  static Insertable<SchemeOfWorkData> custom({
    Expression<int>? id,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
    });
  }

  SchemeOfWorkCompanion copyWith({Value<int>? id}) {
    return SchemeOfWorkCompanion(
      id: id ?? this.id,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SchemeOfWorkCompanion(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }
}

class $ExamsTable extends Exams with TableInfo<$ExamsTable, Exam> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExamsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _subjectMeta =
      const VerificationMeta('subject');
  @override
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
      'subject', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _classLevelMeta =
      const VerificationMeta('classLevel');
  @override
  late final GeneratedColumn<String> classLevel = GeneratedColumn<String>(
      'class_level', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _topicMeta = const VerificationMeta('topic');
  @override
  late final GeneratedColumn<String> topic = GeneratedColumn<String>(
      'topic', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _difficultyMeta =
      const VerificationMeta('difficulty');
  @override
  late final GeneratedColumn<String> difficulty = GeneratedColumn<String>(
      'difficulty', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _curriculumMeta =
      const VerificationMeta('curriculum');
  @override
  late final GeneratedColumn<String> curriculum = GeneratedColumn<String>(
      'curriculum', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        subject,
        classLevel,
        topic,
        difficulty,
        curriculum,
        content,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'exams';
  @override
  VerificationContext validateIntegrity(Insertable<Exam> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('subject')) {
      context.handle(_subjectMeta,
          subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta));
    } else if (isInserting) {
      context.missing(_subjectMeta);
    }
    if (data.containsKey('class_level')) {
      context.handle(
          _classLevelMeta,
          classLevel.isAcceptableOrUnknown(
              data['class_level']!, _classLevelMeta));
    } else if (isInserting) {
      context.missing(_classLevelMeta);
    }
    if (data.containsKey('topic')) {
      context.handle(
          _topicMeta, topic.isAcceptableOrUnknown(data['topic']!, _topicMeta));
    } else if (isInserting) {
      context.missing(_topicMeta);
    }
    if (data.containsKey('difficulty')) {
      context.handle(
          _difficultyMeta,
          difficulty.isAcceptableOrUnknown(
              data['difficulty']!, _difficultyMeta));
    } else if (isInserting) {
      context.missing(_difficultyMeta);
    }
    if (data.containsKey('curriculum')) {
      context.handle(
          _curriculumMeta,
          curriculum.isAcceptableOrUnknown(
              data['curriculum']!, _curriculumMeta));
    } else if (isInserting) {
      context.missing(_curriculumMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Exam map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Exam(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      subject: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}subject'])!,
      classLevel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}class_level'])!,
      topic: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}topic'])!,
      difficulty: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}difficulty'])!,
      curriculum: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}curriculum'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ExamsTable createAlias(String alias) {
    return $ExamsTable(attachedDatabase, alias);
  }
}

class Exam extends DataClass implements Insertable<Exam> {
  final int id;
  final String subject;
  final String classLevel;
  final String topic;
  final String difficulty;
  final String curriculum;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Exam(
      {required this.id,
      required this.subject,
      required this.classLevel,
      required this.topic,
      required this.difficulty,
      required this.curriculum,
      required this.content,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['subject'] = Variable<String>(subject);
    map['class_level'] = Variable<String>(classLevel);
    map['topic'] = Variable<String>(topic);
    map['difficulty'] = Variable<String>(difficulty);
    map['curriculum'] = Variable<String>(curriculum);
    map['content'] = Variable<String>(content);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ExamsCompanion toCompanion(bool nullToAbsent) {
    return ExamsCompanion(
      id: Value(id),
      subject: Value(subject),
      classLevel: Value(classLevel),
      topic: Value(topic),
      difficulty: Value(difficulty),
      curriculum: Value(curriculum),
      content: Value(content),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Exam.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Exam(
      id: serializer.fromJson<int>(json['id']),
      subject: serializer.fromJson<String>(json['subject']),
      classLevel: serializer.fromJson<String>(json['classLevel']),
      topic: serializer.fromJson<String>(json['topic']),
      difficulty: serializer.fromJson<String>(json['difficulty']),
      curriculum: serializer.fromJson<String>(json['curriculum']),
      content: serializer.fromJson<String>(json['content']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'subject': serializer.toJson<String>(subject),
      'classLevel': serializer.toJson<String>(classLevel),
      'topic': serializer.toJson<String>(topic),
      'difficulty': serializer.toJson<String>(difficulty),
      'curriculum': serializer.toJson<String>(curriculum),
      'content': serializer.toJson<String>(content),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Exam copyWith(
          {int? id,
          String? subject,
          String? classLevel,
          String? topic,
          String? difficulty,
          String? curriculum,
          String? content,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Exam(
        id: id ?? this.id,
        subject: subject ?? this.subject,
        classLevel: classLevel ?? this.classLevel,
        topic: topic ?? this.topic,
        difficulty: difficulty ?? this.difficulty,
        curriculum: curriculum ?? this.curriculum,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Exam copyWithCompanion(ExamsCompanion data) {
    return Exam(
      id: data.id.present ? data.id.value : this.id,
      subject: data.subject.present ? data.subject.value : this.subject,
      classLevel:
          data.classLevel.present ? data.classLevel.value : this.classLevel,
      topic: data.topic.present ? data.topic.value : this.topic,
      difficulty:
          data.difficulty.present ? data.difficulty.value : this.difficulty,
      curriculum:
          data.curriculum.present ? data.curriculum.value : this.curriculum,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Exam(')
          ..write('id: $id, ')
          ..write('subject: $subject, ')
          ..write('classLevel: $classLevel, ')
          ..write('topic: $topic, ')
          ..write('difficulty: $difficulty, ')
          ..write('curriculum: $curriculum, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, subject, classLevel, topic, difficulty,
      curriculum, content, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Exam &&
          other.id == this.id &&
          other.subject == this.subject &&
          other.classLevel == this.classLevel &&
          other.topic == this.topic &&
          other.difficulty == this.difficulty &&
          other.curriculum == this.curriculum &&
          other.content == this.content &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ExamsCompanion extends UpdateCompanion<Exam> {
  final Value<int> id;
  final Value<String> subject;
  final Value<String> classLevel;
  final Value<String> topic;
  final Value<String> difficulty;
  final Value<String> curriculum;
  final Value<String> content;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const ExamsCompanion({
    this.id = const Value.absent(),
    this.subject = const Value.absent(),
    this.classLevel = const Value.absent(),
    this.topic = const Value.absent(),
    this.difficulty = const Value.absent(),
    this.curriculum = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ExamsCompanion.insert({
    this.id = const Value.absent(),
    required String subject,
    required String classLevel,
    required String topic,
    required String difficulty,
    required String curriculum,
    required String content,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  })  : subject = Value(subject),
        classLevel = Value(classLevel),
        topic = Value(topic),
        difficulty = Value(difficulty),
        curriculum = Value(curriculum),
        content = Value(content);
  static Insertable<Exam> custom({
    Expression<int>? id,
    Expression<String>? subject,
    Expression<String>? classLevel,
    Expression<String>? topic,
    Expression<String>? difficulty,
    Expression<String>? curriculum,
    Expression<String>? content,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (subject != null) 'subject': subject,
      if (classLevel != null) 'class_level': classLevel,
      if (topic != null) 'topic': topic,
      if (difficulty != null) 'difficulty': difficulty,
      if (curriculum != null) 'curriculum': curriculum,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ExamsCompanion copyWith(
      {Value<int>? id,
      Value<String>? subject,
      Value<String>? classLevel,
      Value<String>? topic,
      Value<String>? difficulty,
      Value<String>? curriculum,
      Value<String>? content,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt}) {
    return ExamsCompanion(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      classLevel: classLevel ?? this.classLevel,
      topic: topic ?? this.topic,
      difficulty: difficulty ?? this.difficulty,
      curriculum: curriculum ?? this.curriculum,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (classLevel.present) {
      map['class_level'] = Variable<String>(classLevel.value);
    }
    if (topic.present) {
      map['topic'] = Variable<String>(topic.value);
    }
    if (difficulty.present) {
      map['difficulty'] = Variable<String>(difficulty.value);
    }
    if (curriculum.present) {
      map['curriculum'] = Variable<String>(curriculum.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExamsCompanion(')
          ..write('id: $id, ')
          ..write('subject: $subject, ')
          ..write('classLevel: $classLevel, ')
          ..write('topic: $topic, ')
          ..write('difficulty: $difficulty, ')
          ..write('curriculum: $curriculum, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ProgressLogsTable extends ProgressLogs
    with TableInfo<$ProgressLogsTable, ProgressLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgressLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  @override
  List<GeneratedColumn> get $columns => [id];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'progress_logs';
  @override
  VerificationContext validateIntegrity(Insertable<ProgressLog> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProgressLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProgressLog(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
    );
  }

  @override
  $ProgressLogsTable createAlias(String alias) {
    return $ProgressLogsTable(attachedDatabase, alias);
  }
}

class ProgressLog extends DataClass implements Insertable<ProgressLog> {
  final int id;
  const ProgressLog({required this.id});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    return map;
  }

  ProgressLogsCompanion toCompanion(bool nullToAbsent) {
    return ProgressLogsCompanion(
      id: Value(id),
    );
  }

  factory ProgressLog.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProgressLog(
      id: serializer.fromJson<int>(json['id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
    };
  }

  ProgressLog copyWith({int? id}) => ProgressLog(
        id: id ?? this.id,
      );
  ProgressLog copyWithCompanion(ProgressLogsCompanion data) {
    return ProgressLog(
      id: data.id.present ? data.id.value : this.id,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgressLog(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => id.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ProgressLog && other.id == this.id);
}

class ProgressLogsCompanion extends UpdateCompanion<ProgressLog> {
  final Value<int> id;
  const ProgressLogsCompanion({
    this.id = const Value.absent(),
  });
  ProgressLogsCompanion.insert({
    this.id = const Value.absent(),
  });
  static Insertable<ProgressLog> custom({
    Expression<int>? id,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
    });
  }

  ProgressLogsCompanion copyWith({Value<int>? id}) {
    return ProgressLogsCompanion(
      id: id ?? this.id,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgressLogsCompanion(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }
}

class $VaultItemsTable extends VaultItems
    with TableInfo<$VaultItemsTable, VaultItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VaultItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _serverIdMeta =
      const VerificationMeta('serverId');
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
      'server_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _subjectMeta =
      const VerificationMeta('subject');
  @override
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
      'subject', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _classLevelMeta =
      const VerificationMeta('classLevel');
  @override
  late final GeneratedColumn<String> classLevel = GeneratedColumn<String>(
      'class_level', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _curriculumMeta =
      const VerificationMeta('curriculum');
  @override
  late final GeneratedColumn<String> curriculum = GeneratedColumn<String>(
      'curriculum', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _authorTeacherIdMeta =
      const VerificationMeta('authorTeacherId');
  @override
  late final GeneratedColumn<String> authorTeacherId = GeneratedColumn<String>(
      'author_teacher_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _authorNameMeta =
      const VerificationMeta('authorName');
  @override
  late final GeneratedColumn<String> authorName = GeneratedColumn<String>(
      'author_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _minTierMeta =
      const VerificationMeta('minTier');
  @override
  late final GeneratedColumn<String> minTier = GeneratedColumn<String>(
      'min_tier', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('free'));
  static const VerificationMeta _creditCostMeta =
      const VerificationMeta('creditCost');
  @override
  late final GeneratedColumn<int> creditCost = GeneratedColumn<int>(
      'credit_cost', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _needsApprovalMeta =
      const VerificationMeta('needsApproval');
  @override
  late final GeneratedColumn<bool> needsApproval = GeneratedColumn<bool>(
      'needs_approval', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("needs_approval" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _approvalStatusMeta =
      const VerificationMeta('approvalStatus');
  @override
  late final GeneratedColumn<String> approvalStatus = GeneratedColumn<String>(
      'approval_status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _rejectionReasonMeta =
      const VerificationMeta('rejectionReason');
  @override
  late final GeneratedColumn<String> rejectionReason = GeneratedColumn<String>(
      'rejection_reason', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _thumbnailUrlMeta =
      const VerificationMeta('thumbnailUrl');
  @override
  late final GeneratedColumn<String> thumbnailUrl = GeneratedColumn<String>(
      'thumbnail_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updateCounterMeta =
      const VerificationMeta('updateCounter');
  @override
  late final GeneratedColumn<int> updateCounter = GeneratedColumn<int>(
      'update_counter', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isDeletedMeta =
      const VerificationMeta('isDeleted');
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
      'is_deleted', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_deleted" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _acquisitionDateMeta =
      const VerificationMeta('acquisitionDate');
  @override
  late final GeneratedColumn<DateTime> acquisitionDate =
      GeneratedColumn<DateTime>('acquisition_date', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _creditSpentBatchIdMeta =
      const VerificationMeta('creditSpentBatchId');
  @override
  late final GeneratedColumn<String> creditSpentBatchId =
      GeneratedColumn<String>('credit_spent_batch_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        serverId,
        title,
        description,
        subject,
        classLevel,
        curriculum,
        content,
        authorTeacherId,
        authorName,
        minTier,
        creditCost,
        needsApproval,
        approvalStatus,
        rejectionReason,
        thumbnailUrl,
        createdAt,
        updatedAt,
        updateCounter,
        isDeleted,
        acquisitionDate,
        creditSpentBatchId
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vault_items';
  @override
  VerificationContext validateIntegrity(Insertable<VaultItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('server_id')) {
      context.handle(_serverIdMeta,
          serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('subject')) {
      context.handle(_subjectMeta,
          subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta));
    } else if (isInserting) {
      context.missing(_subjectMeta);
    }
    if (data.containsKey('class_level')) {
      context.handle(
          _classLevelMeta,
          classLevel.isAcceptableOrUnknown(
              data['class_level']!, _classLevelMeta));
    } else if (isInserting) {
      context.missing(_classLevelMeta);
    }
    if (data.containsKey('curriculum')) {
      context.handle(
          _curriculumMeta,
          curriculum.isAcceptableOrUnknown(
              data['curriculum']!, _curriculumMeta));
    } else if (isInserting) {
      context.missing(_curriculumMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('author_teacher_id')) {
      context.handle(
          _authorTeacherIdMeta,
          authorTeacherId.isAcceptableOrUnknown(
              data['author_teacher_id']!, _authorTeacherIdMeta));
    } else if (isInserting) {
      context.missing(_authorTeacherIdMeta);
    }
    if (data.containsKey('author_name')) {
      context.handle(
          _authorNameMeta,
          authorName.isAcceptableOrUnknown(
              data['author_name']!, _authorNameMeta));
    } else if (isInserting) {
      context.missing(_authorNameMeta);
    }
    if (data.containsKey('min_tier')) {
      context.handle(_minTierMeta,
          minTier.isAcceptableOrUnknown(data['min_tier']!, _minTierMeta));
    }
    if (data.containsKey('credit_cost')) {
      context.handle(
          _creditCostMeta,
          creditCost.isAcceptableOrUnknown(
              data['credit_cost']!, _creditCostMeta));
    }
    if (data.containsKey('needs_approval')) {
      context.handle(
          _needsApprovalMeta,
          needsApproval.isAcceptableOrUnknown(
              data['needs_approval']!, _needsApprovalMeta));
    }
    if (data.containsKey('approval_status')) {
      context.handle(
          _approvalStatusMeta,
          approvalStatus.isAcceptableOrUnknown(
              data['approval_status']!, _approvalStatusMeta));
    }
    if (data.containsKey('rejection_reason')) {
      context.handle(
          _rejectionReasonMeta,
          rejectionReason.isAcceptableOrUnknown(
              data['rejection_reason']!, _rejectionReasonMeta));
    }
    if (data.containsKey('thumbnail_url')) {
      context.handle(
          _thumbnailUrlMeta,
          thumbnailUrl.isAcceptableOrUnknown(
              data['thumbnail_url']!, _thumbnailUrlMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('update_counter')) {
      context.handle(
          _updateCounterMeta,
          updateCounter.isAcceptableOrUnknown(
              data['update_counter']!, _updateCounterMeta));
    }
    if (data.containsKey('is_deleted')) {
      context.handle(_isDeletedMeta,
          isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta));
    }
    if (data.containsKey('acquisition_date')) {
      context.handle(
          _acquisitionDateMeta,
          acquisitionDate.isAcceptableOrUnknown(
              data['acquisition_date']!, _acquisitionDateMeta));
    }
    if (data.containsKey('credit_spent_batch_id')) {
      context.handle(
          _creditSpentBatchIdMeta,
          creditSpentBatchId.isAcceptableOrUnknown(
              data['credit_spent_batch_id']!, _creditSpentBatchIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VaultItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VaultItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      serverId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}server_id']),
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      subject: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}subject'])!,
      classLevel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}class_level'])!,
      curriculum: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}curriculum'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      authorTeacherId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}author_teacher_id'])!,
      authorName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}author_name'])!,
      minTier: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}min_tier'])!,
      creditCost: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}credit_cost'])!,
      needsApproval: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}needs_approval'])!,
      approvalStatus: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}approval_status'])!,
      rejectionReason: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}rejection_reason']),
      thumbnailUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}thumbnail_url']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      updateCounter: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}update_counter'])!,
      isDeleted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_deleted'])!,
      acquisitionDate: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}acquisition_date']),
      creditSpentBatchId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}credit_spent_batch_id']),
    );
  }

  @override
  $VaultItemsTable createAlias(String alias) {
    return $VaultItemsTable(attachedDatabase, alias);
  }
}

class VaultItem extends DataClass implements Insertable<VaultItem> {
  final int id;
  final String? serverId;
  final String title;
  final String description;
  final String subject;
  final String classLevel;
  final String curriculum;
  final String content;
  final String authorTeacherId;
  final String authorName;
  final String minTier;
  final int creditCost;
  final bool needsApproval;
  final String approvalStatus;
  final String? rejectionReason;
  final String? thumbnailUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int updateCounter;
  final bool isDeleted;
  final DateTime? acquisitionDate;
  final String? creditSpentBatchId;
  const VaultItem(
      {required this.id,
      this.serverId,
      required this.title,
      required this.description,
      required this.subject,
      required this.classLevel,
      required this.curriculum,
      required this.content,
      required this.authorTeacherId,
      required this.authorName,
      required this.minTier,
      required this.creditCost,
      required this.needsApproval,
      required this.approvalStatus,
      this.rejectionReason,
      this.thumbnailUrl,
      required this.createdAt,
      required this.updatedAt,
      required this.updateCounter,
      required this.isDeleted,
      this.acquisitionDate,
      this.creditSpentBatchId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    map['title'] = Variable<String>(title);
    map['description'] = Variable<String>(description);
    map['subject'] = Variable<String>(subject);
    map['class_level'] = Variable<String>(classLevel);
    map['curriculum'] = Variable<String>(curriculum);
    map['content'] = Variable<String>(content);
    map['author_teacher_id'] = Variable<String>(authorTeacherId);
    map['author_name'] = Variable<String>(authorName);
    map['min_tier'] = Variable<String>(minTier);
    map['credit_cost'] = Variable<int>(creditCost);
    map['needs_approval'] = Variable<bool>(needsApproval);
    map['approval_status'] = Variable<String>(approvalStatus);
    if (!nullToAbsent || rejectionReason != null) {
      map['rejection_reason'] = Variable<String>(rejectionReason);
    }
    if (!nullToAbsent || thumbnailUrl != null) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['update_counter'] = Variable<int>(updateCounter);
    map['is_deleted'] = Variable<bool>(isDeleted);
    if (!nullToAbsent || acquisitionDate != null) {
      map['acquisition_date'] = Variable<DateTime>(acquisitionDate);
    }
    if (!nullToAbsent || creditSpentBatchId != null) {
      map['credit_spent_batch_id'] = Variable<String>(creditSpentBatchId);
    }
    return map;
  }

  VaultItemsCompanion toCompanion(bool nullToAbsent) {
    return VaultItemsCompanion(
      id: Value(id),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      title: Value(title),
      description: Value(description),
      subject: Value(subject),
      classLevel: Value(classLevel),
      curriculum: Value(curriculum),
      content: Value(content),
      authorTeacherId: Value(authorTeacherId),
      authorName: Value(authorName),
      minTier: Value(minTier),
      creditCost: Value(creditCost),
      needsApproval: Value(needsApproval),
      approvalStatus: Value(approvalStatus),
      rejectionReason: rejectionReason == null && nullToAbsent
          ? const Value.absent()
          : Value(rejectionReason),
      thumbnailUrl: thumbnailUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailUrl),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      updateCounter: Value(updateCounter),
      isDeleted: Value(isDeleted),
      acquisitionDate: acquisitionDate == null && nullToAbsent
          ? const Value.absent()
          : Value(acquisitionDate),
      creditSpentBatchId: creditSpentBatchId == null && nullToAbsent
          ? const Value.absent()
          : Value(creditSpentBatchId),
    );
  }

  factory VaultItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VaultItem(
      id: serializer.fromJson<int>(json['id']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      subject: serializer.fromJson<String>(json['subject']),
      classLevel: serializer.fromJson<String>(json['classLevel']),
      curriculum: serializer.fromJson<String>(json['curriculum']),
      content: serializer.fromJson<String>(json['content']),
      authorTeacherId: serializer.fromJson<String>(json['authorTeacherId']),
      authorName: serializer.fromJson<String>(json['authorName']),
      minTier: serializer.fromJson<String>(json['minTier']),
      creditCost: serializer.fromJson<int>(json['creditCost']),
      needsApproval: serializer.fromJson<bool>(json['needsApproval']),
      approvalStatus: serializer.fromJson<String>(json['approvalStatus']),
      rejectionReason: serializer.fromJson<String?>(json['rejectionReason']),
      thumbnailUrl: serializer.fromJson<String?>(json['thumbnailUrl']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updateCounter: serializer.fromJson<int>(json['updateCounter']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      acquisitionDate: serializer.fromJson<DateTime?>(json['acquisitionDate']),
      creditSpentBatchId:
          serializer.fromJson<String?>(json['creditSpentBatchId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'serverId': serializer.toJson<String?>(serverId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'subject': serializer.toJson<String>(subject),
      'classLevel': serializer.toJson<String>(classLevel),
      'curriculum': serializer.toJson<String>(curriculum),
      'content': serializer.toJson<String>(content),
      'authorTeacherId': serializer.toJson<String>(authorTeacherId),
      'authorName': serializer.toJson<String>(authorName),
      'minTier': serializer.toJson<String>(minTier),
      'creditCost': serializer.toJson<int>(creditCost),
      'needsApproval': serializer.toJson<bool>(needsApproval),
      'approvalStatus': serializer.toJson<String>(approvalStatus),
      'rejectionReason': serializer.toJson<String?>(rejectionReason),
      'thumbnailUrl': serializer.toJson<String?>(thumbnailUrl),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updateCounter': serializer.toJson<int>(updateCounter),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'acquisitionDate': serializer.toJson<DateTime?>(acquisitionDate),
      'creditSpentBatchId': serializer.toJson<String?>(creditSpentBatchId),
    };
  }

  VaultItem copyWith(
          {int? id,
          Value<String?> serverId = const Value.absent(),
          String? title,
          String? description,
          String? subject,
          String? classLevel,
          String? curriculum,
          String? content,
          String? authorTeacherId,
          String? authorName,
          String? minTier,
          int? creditCost,
          bool? needsApproval,
          String? approvalStatus,
          Value<String?> rejectionReason = const Value.absent(),
          Value<String?> thumbnailUrl = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt,
          int? updateCounter,
          bool? isDeleted,
          Value<DateTime?> acquisitionDate = const Value.absent(),
          Value<String?> creditSpentBatchId = const Value.absent()}) =>
      VaultItem(
        id: id ?? this.id,
        serverId: serverId.present ? serverId.value : this.serverId,
        title: title ?? this.title,
        description: description ?? this.description,
        subject: subject ?? this.subject,
        classLevel: classLevel ?? this.classLevel,
        curriculum: curriculum ?? this.curriculum,
        content: content ?? this.content,
        authorTeacherId: authorTeacherId ?? this.authorTeacherId,
        authorName: authorName ?? this.authorName,
        minTier: minTier ?? this.minTier,
        creditCost: creditCost ?? this.creditCost,
        needsApproval: needsApproval ?? this.needsApproval,
        approvalStatus: approvalStatus ?? this.approvalStatus,
        rejectionReason: rejectionReason.present
            ? rejectionReason.value
            : this.rejectionReason,
        thumbnailUrl:
            thumbnailUrl.present ? thumbnailUrl.value : this.thumbnailUrl,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        updateCounter: updateCounter ?? this.updateCounter,
        isDeleted: isDeleted ?? this.isDeleted,
        acquisitionDate: acquisitionDate.present
            ? acquisitionDate.value
            : this.acquisitionDate,
        creditSpentBatchId: creditSpentBatchId.present
            ? creditSpentBatchId.value
            : this.creditSpentBatchId,
      );
  VaultItem copyWithCompanion(VaultItemsCompanion data) {
    return VaultItem(
      id: data.id.present ? data.id.value : this.id,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      title: data.title.present ? data.title.value : this.title,
      description:
          data.description.present ? data.description.value : this.description,
      subject: data.subject.present ? data.subject.value : this.subject,
      classLevel:
          data.classLevel.present ? data.classLevel.value : this.classLevel,
      curriculum:
          data.curriculum.present ? data.curriculum.value : this.curriculum,
      content: data.content.present ? data.content.value : this.content,
      authorTeacherId: data.authorTeacherId.present
          ? data.authorTeacherId.value
          : this.authorTeacherId,
      authorName:
          data.authorName.present ? data.authorName.value : this.authorName,
      minTier: data.minTier.present ? data.minTier.value : this.minTier,
      creditCost:
          data.creditCost.present ? data.creditCost.value : this.creditCost,
      needsApproval: data.needsApproval.present
          ? data.needsApproval.value
          : this.needsApproval,
      approvalStatus: data.approvalStatus.present
          ? data.approvalStatus.value
          : this.approvalStatus,
      rejectionReason: data.rejectionReason.present
          ? data.rejectionReason.value
          : this.rejectionReason,
      thumbnailUrl: data.thumbnailUrl.present
          ? data.thumbnailUrl.value
          : this.thumbnailUrl,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updateCounter: data.updateCounter.present
          ? data.updateCounter.value
          : this.updateCounter,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      acquisitionDate: data.acquisitionDate.present
          ? data.acquisitionDate.value
          : this.acquisitionDate,
      creditSpentBatchId: data.creditSpentBatchId.present
          ? data.creditSpentBatchId.value
          : this.creditSpentBatchId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VaultItem(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('subject: $subject, ')
          ..write('classLevel: $classLevel, ')
          ..write('curriculum: $curriculum, ')
          ..write('content: $content, ')
          ..write('authorTeacherId: $authorTeacherId, ')
          ..write('authorName: $authorName, ')
          ..write('minTier: $minTier, ')
          ..write('creditCost: $creditCost, ')
          ..write('needsApproval: $needsApproval, ')
          ..write('approvalStatus: $approvalStatus, ')
          ..write('rejectionReason: $rejectionReason, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updateCounter: $updateCounter, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('acquisitionDate: $acquisitionDate, ')
          ..write('creditSpentBatchId: $creditSpentBatchId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        serverId,
        title,
        description,
        subject,
        classLevel,
        curriculum,
        content,
        authorTeacherId,
        authorName,
        minTier,
        creditCost,
        needsApproval,
        approvalStatus,
        rejectionReason,
        thumbnailUrl,
        createdAt,
        updatedAt,
        updateCounter,
        isDeleted,
        acquisitionDate,
        creditSpentBatchId
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VaultItem &&
          other.id == this.id &&
          other.serverId == this.serverId &&
          other.title == this.title &&
          other.description == this.description &&
          other.subject == this.subject &&
          other.classLevel == this.classLevel &&
          other.curriculum == this.curriculum &&
          other.content == this.content &&
          other.authorTeacherId == this.authorTeacherId &&
          other.authorName == this.authorName &&
          other.minTier == this.minTier &&
          other.creditCost == this.creditCost &&
          other.needsApproval == this.needsApproval &&
          other.approvalStatus == this.approvalStatus &&
          other.rejectionReason == this.rejectionReason &&
          other.thumbnailUrl == this.thumbnailUrl &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.updateCounter == this.updateCounter &&
          other.isDeleted == this.isDeleted &&
          other.acquisitionDate == this.acquisitionDate &&
          other.creditSpentBatchId == this.creditSpentBatchId);
}

class VaultItemsCompanion extends UpdateCompanion<VaultItem> {
  final Value<int> id;
  final Value<String?> serverId;
  final Value<String> title;
  final Value<String> description;
  final Value<String> subject;
  final Value<String> classLevel;
  final Value<String> curriculum;
  final Value<String> content;
  final Value<String> authorTeacherId;
  final Value<String> authorName;
  final Value<String> minTier;
  final Value<int> creditCost;
  final Value<bool> needsApproval;
  final Value<String> approvalStatus;
  final Value<String?> rejectionReason;
  final Value<String?> thumbnailUrl;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> updateCounter;
  final Value<bool> isDeleted;
  final Value<DateTime?> acquisitionDate;
  final Value<String?> creditSpentBatchId;
  const VaultItemsCompanion({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.subject = const Value.absent(),
    this.classLevel = const Value.absent(),
    this.curriculum = const Value.absent(),
    this.content = const Value.absent(),
    this.authorTeacherId = const Value.absent(),
    this.authorName = const Value.absent(),
    this.minTier = const Value.absent(),
    this.creditCost = const Value.absent(),
    this.needsApproval = const Value.absent(),
    this.approvalStatus = const Value.absent(),
    this.rejectionReason = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updateCounter = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.acquisitionDate = const Value.absent(),
    this.creditSpentBatchId = const Value.absent(),
  });
  VaultItemsCompanion.insert({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    required String title,
    required String description,
    required String subject,
    required String classLevel,
    required String curriculum,
    required String content,
    required String authorTeacherId,
    required String authorName,
    this.minTier = const Value.absent(),
    this.creditCost = const Value.absent(),
    this.needsApproval = const Value.absent(),
    this.approvalStatus = const Value.absent(),
    this.rejectionReason = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updateCounter = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.acquisitionDate = const Value.absent(),
    this.creditSpentBatchId = const Value.absent(),
  })  : title = Value(title),
        description = Value(description),
        subject = Value(subject),
        classLevel = Value(classLevel),
        curriculum = Value(curriculum),
        content = Value(content),
        authorTeacherId = Value(authorTeacherId),
        authorName = Value(authorName);
  static Insertable<VaultItem> custom({
    Expression<int>? id,
    Expression<String>? serverId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? subject,
    Expression<String>? classLevel,
    Expression<String>? curriculum,
    Expression<String>? content,
    Expression<String>? authorTeacherId,
    Expression<String>? authorName,
    Expression<String>? minTier,
    Expression<int>? creditCost,
    Expression<bool>? needsApproval,
    Expression<String>? approvalStatus,
    Expression<String>? rejectionReason,
    Expression<String>? thumbnailUrl,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? updateCounter,
    Expression<bool>? isDeleted,
    Expression<DateTime>? acquisitionDate,
    Expression<String>? creditSpentBatchId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (subject != null) 'subject': subject,
      if (classLevel != null) 'class_level': classLevel,
      if (curriculum != null) 'curriculum': curriculum,
      if (content != null) 'content': content,
      if (authorTeacherId != null) 'author_teacher_id': authorTeacherId,
      if (authorName != null) 'author_name': authorName,
      if (minTier != null) 'min_tier': minTier,
      if (creditCost != null) 'credit_cost': creditCost,
      if (needsApproval != null) 'needs_approval': needsApproval,
      if (approvalStatus != null) 'approval_status': approvalStatus,
      if (rejectionReason != null) 'rejection_reason': rejectionReason,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updateCounter != null) 'update_counter': updateCounter,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (acquisitionDate != null) 'acquisition_date': acquisitionDate,
      if (creditSpentBatchId != null)
        'credit_spent_batch_id': creditSpentBatchId,
    });
  }

  VaultItemsCompanion copyWith(
      {Value<int>? id,
      Value<String?>? serverId,
      Value<String>? title,
      Value<String>? description,
      Value<String>? subject,
      Value<String>? classLevel,
      Value<String>? curriculum,
      Value<String>? content,
      Value<String>? authorTeacherId,
      Value<String>? authorName,
      Value<String>? minTier,
      Value<int>? creditCost,
      Value<bool>? needsApproval,
      Value<String>? approvalStatus,
      Value<String?>? rejectionReason,
      Value<String?>? thumbnailUrl,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? updateCounter,
      Value<bool>? isDeleted,
      Value<DateTime?>? acquisitionDate,
      Value<String?>? creditSpentBatchId}) {
    return VaultItemsCompanion(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      title: title ?? this.title,
      description: description ?? this.description,
      subject: subject ?? this.subject,
      classLevel: classLevel ?? this.classLevel,
      curriculum: curriculum ?? this.curriculum,
      content: content ?? this.content,
      authorTeacherId: authorTeacherId ?? this.authorTeacherId,
      authorName: authorName ?? this.authorName,
      minTier: minTier ?? this.minTier,
      creditCost: creditCost ?? this.creditCost,
      needsApproval: needsApproval ?? this.needsApproval,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updateCounter: updateCounter ?? this.updateCounter,
      isDeleted: isDeleted ?? this.isDeleted,
      acquisitionDate: acquisitionDate ?? this.acquisitionDate,
      creditSpentBatchId: creditSpentBatchId ?? this.creditSpentBatchId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (classLevel.present) {
      map['class_level'] = Variable<String>(classLevel.value);
    }
    if (curriculum.present) {
      map['curriculum'] = Variable<String>(curriculum.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (authorTeacherId.present) {
      map['author_teacher_id'] = Variable<String>(authorTeacherId.value);
    }
    if (authorName.present) {
      map['author_name'] = Variable<String>(authorName.value);
    }
    if (minTier.present) {
      map['min_tier'] = Variable<String>(minTier.value);
    }
    if (creditCost.present) {
      map['credit_cost'] = Variable<int>(creditCost.value);
    }
    if (needsApproval.present) {
      map['needs_approval'] = Variable<bool>(needsApproval.value);
    }
    if (approvalStatus.present) {
      map['approval_status'] = Variable<String>(approvalStatus.value);
    }
    if (rejectionReason.present) {
      map['rejection_reason'] = Variable<String>(rejectionReason.value);
    }
    if (thumbnailUrl.present) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updateCounter.present) {
      map['update_counter'] = Variable<int>(updateCounter.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (acquisitionDate.present) {
      map['acquisition_date'] = Variable<DateTime>(acquisitionDate.value);
    }
    if (creditSpentBatchId.present) {
      map['credit_spent_batch_id'] = Variable<String>(creditSpentBatchId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VaultItemsCompanion(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('subject: $subject, ')
          ..write('classLevel: $classLevel, ')
          ..write('curriculum: $curriculum, ')
          ..write('content: $content, ')
          ..write('authorTeacherId: $authorTeacherId, ')
          ..write('authorName: $authorName, ')
          ..write('minTier: $minTier, ')
          ..write('creditCost: $creditCost, ')
          ..write('needsApproval: $needsApproval, ')
          ..write('approvalStatus: $approvalStatus, ')
          ..write('rejectionReason: $rejectionReason, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updateCounter: $updateCounter, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('acquisitionDate: $acquisitionDate, ')
          ..write('creditSpentBatchId: $creditSpentBatchId')
          ..write(')'))
        .toString();
  }
}

class $SecurityConfigTable extends SecurityConfig
    with TableInfo<$SecurityConfigTable, SecurityConfigData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SecurityConfigTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _isLockedMeta =
      const VerificationMeta('isLocked');
  @override
  late final GeneratedColumn<bool> isLocked = GeneratedColumn<bool>(
      'is_locked', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_locked" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _lastSeenTimeMeta =
      const VerificationMeta('lastSeenTime');
  @override
  late final GeneratedColumn<DateTime> lastSeenTime = GeneratedColumn<DateTime>(
      'last_seen_time', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _lastKnownGoodTimeMeta =
      const VerificationMeta('lastKnownGoodTime');
  @override
  late final GeneratedColumn<DateTime> lastKnownGoodTime =
      GeneratedColumn<DateTime>('last_known_good_time', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _monotonicLastSeenMeta =
      const VerificationMeta('monotonicLastSeen');
  @override
  late final GeneratedColumn<double> monotonicLastSeen =
      GeneratedColumn<double>('monotonic_last_seen', aliasedName, true,
          type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _offlineCreditsMeta =
      const VerificationMeta('offlineCredits');
  @override
  late final GeneratedColumn<int> offlineCredits = GeneratedColumn<int>(
      'offline_credits', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(3));
  static const VerificationMeta _creditSpentIdsLocalMeta =
      const VerificationMeta('creditSpentIdsLocal');
  @override
  late final GeneratedColumn<String> creditSpentIdsLocal =
      GeneratedColumn<String>('credit_spent_ids_local', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant('[]'));
  static const VerificationMeta _creditServerCounterMeta =
      const VerificationMeta('creditServerCounter');
  @override
  late final GeneratedColumn<int> creditServerCounter = GeneratedColumn<int>(
      'credit_server_counter', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _creditSpentBatchIdMeta =
      const VerificationMeta('creditSpentBatchId');
  @override
  late final GeneratedColumn<String> creditSpentBatchId =
      GeneratedColumn<String>('credit_spent_batch_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastCreditRefillServerTimeMeta =
      const VerificationMeta('lastCreditRefillServerTime');
  @override
  late final GeneratedColumn<DateTime> lastCreditRefillServerTime =
      GeneratedColumn<DateTime>(
          'last_credit_refill_server_time', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _lastPullTimestampMeta =
      const VerificationMeta('lastPullTimestamp');
  @override
  late final GeneratedColumn<DateTime> lastPullTimestamp =
      GeneratedColumn<DateTime>('last_pull_timestamp', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _syncCursorMeta =
      const VerificationMeta('syncCursor');
  @override
  late final GeneratedColumn<String> syncCursor = GeneratedColumn<String>(
      'sync_cursor', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastSyncAttemptTimeMeta =
      const VerificationMeta('lastSyncAttemptTime');
  @override
  late final GeneratedColumn<DateTime> lastSyncAttemptTime =
      GeneratedColumn<DateTime>('last_sync_attempt_time', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _syncCooldownUntilMeta =
      const VerificationMeta('syncCooldownUntil');
  @override
  late final GeneratedColumn<DateTime> syncCooldownUntil =
      GeneratedColumn<DateTime>('sync_cooldown_until', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _lastRealtimeEventIdMeta =
      const VerificationMeta('lastRealtimeEventId');
  @override
  late final GeneratedColumn<int> lastRealtimeEventId = GeneratedColumn<int>(
      'last_realtime_event_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _heartbeatLastSuccessMeta =
      const VerificationMeta('heartbeatLastSuccess');
  @override
  late final GeneratedColumn<DateTime> heartbeatLastSuccess =
      GeneratedColumn<DateTime>('heartbeat_last_success', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _lastVacuumDateMeta =
      const VerificationMeta('lastVacuumDate');
  @override
  late final GeneratedColumn<DateTime> lastVacuumDate =
      GeneratedColumn<DateTime>('last_vacuum_date', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _encryptionKeyWrappedMeta =
      const VerificationMeta('encryptionKeyWrapped');
  @override
  late final GeneratedColumn<String> encryptionKeyWrapped =
      GeneratedColumn<String>('encryption_key_wrapped', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _encryptionRecoveryNeededMeta =
      const VerificationMeta('encryptionRecoveryNeeded');
  @override
  late final GeneratedColumn<bool> encryptionRecoveryNeeded =
      GeneratedColumn<bool>(
          'encryption_recovery_needed', aliasedName, false,
          type: DriftSqlType.bool,
          requiredDuringInsert: false,
          defaultConstraints: GeneratedColumn.constraintIsAlways(
              'CHECK ("encryption_recovery_needed" IN (0, 1))'),
          defaultValue: const Constant(false));
  static const VerificationMeta _corruptedRecordIdsMeta =
      const VerificationMeta('corruptedRecordIds');
  @override
  late final GeneratedColumn<String> corruptedRecordIds =
      GeneratedColumn<String>('corrupted_record_ids', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant('[]'));
  static const VerificationMeta _lastKnownPasswordHashVersionMeta =
      const VerificationMeta('lastKnownPasswordHashVersion');
  @override
  late final GeneratedColumn<int> lastKnownPasswordHashVersion =
      GeneratedColumn<int>(
          'last_known_password_hash_version', aliasedName, false,
          type: DriftSqlType.int,
          requiredDuringInsert: false,
          defaultValue: const Constant(1));
  static const VerificationMeta _sessionKeyEncryptedMeta =
      const VerificationMeta('sessionKeyEncrypted');
  @override
  late final GeneratedColumn<String> sessionKeyEncrypted =
      GeneratedColumn<String>('session_key_encrypted', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sessionKeyExpiryMeta =
      const VerificationMeta('sessionKeyExpiry');
  @override
  late final GeneratedColumn<DateTime> sessionKeyExpiry =
      GeneratedColumn<DateTime>('session_key_expiry', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _syncPendingAfterBiometricTimeoutMeta =
      const VerificationMeta('syncPendingAfterBiometricTimeout');
  @override
  late final GeneratedColumn<bool> syncPendingAfterBiometricTimeout =
      GeneratedColumn<bool>(
          'sync_pending_after_biometric_timeout', aliasedName, false,
          type: DriftSqlType.bool,
          requiredDuringInsert: false,
          defaultConstraints: GeneratedColumn.constraintIsAlways(
              'CHECK ("sync_pending_after_biometric_timeout" IN (0, 1))'),
          defaultValue: const Constant(false));
  static const VerificationMeta _currentDeviceIdMeta =
      const VerificationMeta('currentDeviceId');
  @override
  late final GeneratedColumn<String> currentDeviceId = GeneratedColumn<String>(
      'current_device_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _pendingDbReplacementMeta =
      const VerificationMeta('pendingDbReplacement');
  @override
  late final GeneratedColumn<bool> pendingDbReplacement = GeneratedColumn<bool>(
      'pending_db_replacement', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("pending_db_replacement" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _vacuumedDbPathMeta =
      const VerificationMeta('vacuumedDbPath');
  @override
  late final GeneratedColumn<String> vacuumedDbPath = GeneratedColumn<String>(
      'vacuumed_db_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        isLocked,
        lastSeenTime,
        lastKnownGoodTime,
        monotonicLastSeen,
        offlineCredits,
        creditSpentIdsLocal,
        creditServerCounter,
        creditSpentBatchId,
        lastCreditRefillServerTime,
        lastPullTimestamp,
        syncCursor,
        lastSyncAttemptTime,
        syncCooldownUntil,
        lastRealtimeEventId,
        heartbeatLastSuccess,
        lastVacuumDate,
        encryptionKeyWrapped,
        encryptionRecoveryNeeded,
        corruptedRecordIds,
        lastKnownPasswordHashVersion,
        sessionKeyEncrypted,
        sessionKeyExpiry,
        syncPendingAfterBiometricTimeout,
        currentDeviceId,
        pendingDbReplacement,
        vacuumedDbPath
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'security_config';
  @override
  VerificationContext validateIntegrity(Insertable<SecurityConfigData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('is_locked')) {
      context.handle(_isLockedMeta,
          isLocked.isAcceptableOrUnknown(data['is_locked']!, _isLockedMeta));
    }
    if (data.containsKey('last_seen_time')) {
      context.handle(
          _lastSeenTimeMeta,
          lastSeenTime.isAcceptableOrUnknown(
              data['last_seen_time']!, _lastSeenTimeMeta));
    }
    if (data.containsKey('last_known_good_time')) {
      context.handle(
          _lastKnownGoodTimeMeta,
          lastKnownGoodTime.isAcceptableOrUnknown(
              data['last_known_good_time']!, _lastKnownGoodTimeMeta));
    }
    if (data.containsKey('monotonic_last_seen')) {
      context.handle(
          _monotonicLastSeenMeta,
          monotonicLastSeen.isAcceptableOrUnknown(
              data['monotonic_last_seen']!, _monotonicLastSeenMeta));
    }
    if (data.containsKey('offline_credits')) {
      context.handle(
          _offlineCreditsMeta,
          offlineCredits.isAcceptableOrUnknown(
              data['offline_credits']!, _offlineCreditsMeta));
    }
    if (data.containsKey('credit_spent_ids_local')) {
      context.handle(
          _creditSpentIdsLocalMeta,
          creditSpentIdsLocal.isAcceptableOrUnknown(
              data['credit_spent_ids_local']!, _creditSpentIdsLocalMeta));
    }
    if (data.containsKey('credit_server_counter')) {
      context.handle(
          _creditServerCounterMeta,
          creditServerCounter.isAcceptableOrUnknown(
              data['credit_server_counter']!, _creditServerCounterMeta));
    }
    if (data.containsKey('credit_spent_batch_id')) {
      context.handle(
          _creditSpentBatchIdMeta,
          creditSpentBatchId.isAcceptableOrUnknown(
              data['credit_spent_batch_id']!, _creditSpentBatchIdMeta));
    }
    if (data.containsKey('last_credit_refill_server_time')) {
      context.handle(
          _lastCreditRefillServerTimeMeta,
          lastCreditRefillServerTime.isAcceptableOrUnknown(
              data['last_credit_refill_server_time']!,
              _lastCreditRefillServerTimeMeta));
    }
    if (data.containsKey('last_pull_timestamp')) {
      context.handle(
          _lastPullTimestampMeta,
          lastPullTimestamp.isAcceptableOrUnknown(
              data['last_pull_timestamp']!, _lastPullTimestampMeta));
    }
    if (data.containsKey('sync_cursor')) {
      context.handle(
          _syncCursorMeta,
          syncCursor.isAcceptableOrUnknown(
              data['sync_cursor']!, _syncCursorMeta));
    }
    if (data.containsKey('last_sync_attempt_time')) {
      context.handle(
          _lastSyncAttemptTimeMeta,
          lastSyncAttemptTime.isAcceptableOrUnknown(
              data['last_sync_attempt_time']!, _lastSyncAttemptTimeMeta));
    }
    if (data.containsKey('sync_cooldown_until')) {
      context.handle(
          _syncCooldownUntilMeta,
          syncCooldownUntil.isAcceptableOrUnknown(
              data['sync_cooldown_until']!, _syncCooldownUntilMeta));
    }
    if (data.containsKey('last_realtime_event_id')) {
      context.handle(
          _lastRealtimeEventIdMeta,
          lastRealtimeEventId.isAcceptableOrUnknown(
              data['last_realtime_event_id']!, _lastRealtimeEventIdMeta));
    }
    if (data.containsKey('heartbeat_last_success')) {
      context.handle(
          _heartbeatLastSuccessMeta,
          heartbeatLastSuccess.isAcceptableOrUnknown(
              data['heartbeat_last_success']!, _heartbeatLastSuccessMeta));
    }
    if (data.containsKey('last_vacuum_date')) {
      context.handle(
          _lastVacuumDateMeta,
          lastVacuumDate.isAcceptableOrUnknown(
              data['last_vacuum_date']!, _lastVacuumDateMeta));
    }
    if (data.containsKey('encryption_key_wrapped')) {
      context.handle(
          _encryptionKeyWrappedMeta,
          encryptionKeyWrapped.isAcceptableOrUnknown(
              data['encryption_key_wrapped']!, _encryptionKeyWrappedMeta));
    }
    if (data.containsKey('encryption_recovery_needed')) {
      context.handle(
          _encryptionRecoveryNeededMeta,
          encryptionRecoveryNeeded.isAcceptableOrUnknown(
              data['encryption_recovery_needed']!,
              _encryptionRecoveryNeededMeta));
    }
    if (data.containsKey('corrupted_record_ids')) {
      context.handle(
          _corruptedRecordIdsMeta,
          corruptedRecordIds.isAcceptableOrUnknown(
              data['corrupted_record_ids']!, _corruptedRecordIdsMeta));
    }
    if (data.containsKey('last_known_password_hash_version')) {
      context.handle(
          _lastKnownPasswordHashVersionMeta,
          lastKnownPasswordHashVersion.isAcceptableOrUnknown(
              data['last_known_password_hash_version']!,
              _lastKnownPasswordHashVersionMeta));
    }
    if (data.containsKey('session_key_encrypted')) {
      context.handle(
          _sessionKeyEncryptedMeta,
          sessionKeyEncrypted.isAcceptableOrUnknown(
              data['session_key_encrypted']!, _sessionKeyEncryptedMeta));
    }
    if (data.containsKey('session_key_expiry')) {
      context.handle(
          _sessionKeyExpiryMeta,
          sessionKeyExpiry.isAcceptableOrUnknown(
              data['session_key_expiry']!, _sessionKeyExpiryMeta));
    }
    if (data.containsKey('sync_pending_after_biometric_timeout')) {
      context.handle(
          _syncPendingAfterBiometricTimeoutMeta,
          syncPendingAfterBiometricTimeout.isAcceptableOrUnknown(
              data['sync_pending_after_biometric_timeout']!,
              _syncPendingAfterBiometricTimeoutMeta));
    }
    if (data.containsKey('current_device_id')) {
      context.handle(
          _currentDeviceIdMeta,
          currentDeviceId.isAcceptableOrUnknown(
              data['current_device_id']!, _currentDeviceIdMeta));
    } else if (isInserting) {
      context.missing(_currentDeviceIdMeta);
    }
    if (data.containsKey('pending_db_replacement')) {
      context.handle(
          _pendingDbReplacementMeta,
          pendingDbReplacement.isAcceptableOrUnknown(
              data['pending_db_replacement']!, _pendingDbReplacementMeta));
    }
    if (data.containsKey('vacuumed_db_path')) {
      context.handle(
          _vacuumedDbPathMeta,
          vacuumedDbPath.isAcceptableOrUnknown(
              data['vacuumed_db_path']!, _vacuumedDbPathMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SecurityConfigData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SecurityConfigData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      isLocked: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_locked'])!,
      lastSeenTime: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_seen_time'])!,
      lastKnownGoodTime: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime,
          data['${effectivePrefix}last_known_good_time']),
      monotonicLastSeen: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}monotonic_last_seen']),
      offlineCredits: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}offline_credits'])!,
      creditSpentIdsLocal: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}credit_spent_ids_local'])!,
      creditServerCounter: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}credit_server_counter'])!,
      creditSpentBatchId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}credit_spent_batch_id']),
      lastCreditRefillServerTime: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime,
          data['${effectivePrefix}last_credit_refill_server_time']),
      lastPullTimestamp: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_pull_timestamp']),
      syncCursor: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_cursor']),
      lastSyncAttemptTime: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime,
          data['${effectivePrefix}last_sync_attempt_time']),
      syncCooldownUntil: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}sync_cooldown_until']),
      lastRealtimeEventId: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}last_realtime_event_id'])!,
      heartbeatLastSuccess: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime,
          data['${effectivePrefix}heartbeat_last_success']),
      lastVacuumDate: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_vacuum_date']),
      encryptionKeyWrapped: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}encryption_key_wrapped']),
      encryptionRecoveryNeeded: attachedDatabase.typeMapping.read(
          DriftSqlType.bool,
          data['${effectivePrefix}encryption_recovery_needed'])!,
      corruptedRecordIds: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}corrupted_record_ids'])!,
      lastKnownPasswordHashVersion: attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_known_password_hash_version'])!,
      sessionKeyEncrypted: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}session_key_encrypted']),
      sessionKeyExpiry: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}session_key_expiry']),
      syncPendingAfterBiometricTimeout: attachedDatabase.typeMapping.read(
          DriftSqlType.bool,
          data['${effectivePrefix}sync_pending_after_biometric_timeout'])!,
      currentDeviceId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}current_device_id'])!,
      pendingDbReplacement: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}pending_db_replacement'])!,
      vacuumedDbPath: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}vacuumed_db_path']),
    );
  }

  @override
  $SecurityConfigTable createAlias(String alias) {
    return $SecurityConfigTable(attachedDatabase, alias);
  }
}

class SecurityConfigData extends DataClass
    implements Insertable<SecurityConfigData> {
  final int id;
  final bool isLocked;
  final DateTime lastSeenTime;
  final DateTime? lastKnownGoodTime;
  final double? monotonicLastSeen;
  final int offlineCredits;
  final String creditSpentIdsLocal;
  final int creditServerCounter;
  final String? creditSpentBatchId;
  final DateTime? lastCreditRefillServerTime;
  final DateTime? lastPullTimestamp;
  final String? syncCursor;
  final DateTime? lastSyncAttemptTime;
  final DateTime? syncCooldownUntil;
  final int lastRealtimeEventId;
  final DateTime? heartbeatLastSuccess;
  final DateTime? lastVacuumDate;
  final String? encryptionKeyWrapped;
  final bool encryptionRecoveryNeeded;
  final String corruptedRecordIds;
  final int lastKnownPasswordHashVersion;
  final String? sessionKeyEncrypted;
  final DateTime? sessionKeyExpiry;
  final bool syncPendingAfterBiometricTimeout;
  final String currentDeviceId;
  final bool pendingDbReplacement;
  final String? vacuumedDbPath;
  const SecurityConfigData(
      {required this.id,
      required this.isLocked,
      required this.lastSeenTime,
      this.lastKnownGoodTime,
      this.monotonicLastSeen,
      required this.offlineCredits,
      required this.creditSpentIdsLocal,
      required this.creditServerCounter,
      this.creditSpentBatchId,
      this.lastCreditRefillServerTime,
      this.lastPullTimestamp,
      this.syncCursor,
      this.lastSyncAttemptTime,
      this.syncCooldownUntil,
      required this.lastRealtimeEventId,
      this.heartbeatLastSuccess,
      this.lastVacuumDate,
      this.encryptionKeyWrapped,
      required this.encryptionRecoveryNeeded,
      required this.corruptedRecordIds,
      required this.lastKnownPasswordHashVersion,
      this.sessionKeyEncrypted,
      this.sessionKeyExpiry,
      required this.syncPendingAfterBiometricTimeout,
      required this.currentDeviceId,
      required this.pendingDbReplacement,
      this.vacuumedDbPath});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['is_locked'] = Variable<bool>(isLocked);
    map['last_seen_time'] = Variable<DateTime>(lastSeenTime);
    if (!nullToAbsent || lastKnownGoodTime != null) {
      map['last_known_good_time'] = Variable<DateTime>(lastKnownGoodTime);
    }
    if (!nullToAbsent || monotonicLastSeen != null) {
      map['monotonic_last_seen'] = Variable<double>(monotonicLastSeen);
    }
    map['offline_credits'] = Variable<int>(offlineCredits);
    map['credit_spent_ids_local'] = Variable<String>(creditSpentIdsLocal);
    map['credit_server_counter'] = Variable<int>(creditServerCounter);
    if (!nullToAbsent || creditSpentBatchId != null) {
      map['credit_spent_batch_id'] = Variable<String>(creditSpentBatchId);
    }
    if (!nullToAbsent || lastCreditRefillServerTime != null) {
      map['last_credit_refill_server_time'] =
          Variable<DateTime>(lastCreditRefillServerTime);
    }
    if (!nullToAbsent || lastPullTimestamp != null) {
      map['last_pull_timestamp'] = Variable<DateTime>(lastPullTimestamp);
    }
    if (!nullToAbsent || syncCursor != null) {
      map['sync_cursor'] = Variable<String>(syncCursor);
    }
    if (!nullToAbsent || lastSyncAttemptTime != null) {
      map['last_sync_attempt_time'] = Variable<DateTime>(lastSyncAttemptTime);
    }
    if (!nullToAbsent || syncCooldownUntil != null) {
      map['sync_cooldown_until'] = Variable<DateTime>(syncCooldownUntil);
    }
    map['last_realtime_event_id'] = Variable<int>(lastRealtimeEventId);
    if (!nullToAbsent || heartbeatLastSuccess != null) {
      map['heartbeat_last_success'] = Variable<DateTime>(heartbeatLastSuccess);
    }
    if (!nullToAbsent || lastVacuumDate != null) {
      map['last_vacuum_date'] = Variable<DateTime>(lastVacuumDate);
    }
    if (!nullToAbsent || encryptionKeyWrapped != null) {
      map['encryption_key_wrapped'] = Variable<String>(encryptionKeyWrapped);
    }
    map['encryption_recovery_needed'] =
        Variable<bool>(encryptionRecoveryNeeded);
    map['corrupted_record_ids'] = Variable<String>(corruptedRecordIds);
    map['last_known_password_hash_version'] =
        Variable<int>(lastKnownPasswordHashVersion);
    if (!nullToAbsent || sessionKeyEncrypted != null) {
      map['session_key_encrypted'] = Variable<String>(sessionKeyEncrypted);
    }
    if (!nullToAbsent || sessionKeyExpiry != null) {
      map['session_key_expiry'] = Variable<DateTime>(sessionKeyExpiry);
    }
    map['sync_pending_after_biometric_timeout'] =
        Variable<bool>(syncPendingAfterBiometricTimeout);
    map['current_device_id'] = Variable<String>(currentDeviceId);
    map['pending_db_replacement'] = Variable<bool>(pendingDbReplacement);
    if (!nullToAbsent || vacuumedDbPath != null) {
      map['vacuumed_db_path'] = Variable<String>(vacuumedDbPath);
    }
    return map;
  }

  SecurityConfigCompanion toCompanion(bool nullToAbsent) {
    return SecurityConfigCompanion(
      id: Value(id),
      isLocked: Value(isLocked),
      lastSeenTime: Value(lastSeenTime),
      lastKnownGoodTime: lastKnownGoodTime == null && nullToAbsent
          ? const Value.absent()
          : Value(lastKnownGoodTime),
      monotonicLastSeen: monotonicLastSeen == null && nullToAbsent
          ? const Value.absent()
          : Value(monotonicLastSeen),
      offlineCredits: Value(offlineCredits),
      creditSpentIdsLocal: Value(creditSpentIdsLocal),
      creditServerCounter: Value(creditServerCounter),
      creditSpentBatchId: creditSpentBatchId == null && nullToAbsent
          ? const Value.absent()
          : Value(creditSpentBatchId),
      lastCreditRefillServerTime:
          lastCreditRefillServerTime == null && nullToAbsent
              ? const Value.absent()
              : Value(lastCreditRefillServerTime),
      lastPullTimestamp: lastPullTimestamp == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPullTimestamp),
      syncCursor: syncCursor == null && nullToAbsent
          ? const Value.absent()
          : Value(syncCursor),
      lastSyncAttemptTime: lastSyncAttemptTime == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncAttemptTime),
      syncCooldownUntil: syncCooldownUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(syncCooldownUntil),
      lastRealtimeEventId: Value(lastRealtimeEventId),
      heartbeatLastSuccess: heartbeatLastSuccess == null && nullToAbsent
          ? const Value.absent()
          : Value(heartbeatLastSuccess),
      lastVacuumDate: lastVacuumDate == null && nullToAbsent
          ? const Value.absent()
          : Value(lastVacuumDate),
      encryptionKeyWrapped: encryptionKeyWrapped == null && nullToAbsent
          ? const Value.absent()
          : Value(encryptionKeyWrapped),
      encryptionRecoveryNeeded: Value(encryptionRecoveryNeeded),
      corruptedRecordIds: Value(corruptedRecordIds),
      lastKnownPasswordHashVersion: Value(lastKnownPasswordHashVersion),
      sessionKeyEncrypted: sessionKeyEncrypted == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionKeyEncrypted),
      sessionKeyExpiry: sessionKeyExpiry == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionKeyExpiry),
      syncPendingAfterBiometricTimeout: Value(syncPendingAfterBiometricTimeout),
      currentDeviceId: Value(currentDeviceId),
      pendingDbReplacement: Value(pendingDbReplacement),
      vacuumedDbPath: vacuumedDbPath == null && nullToAbsent
          ? const Value.absent()
          : Value(vacuumedDbPath),
    );
  }

  factory SecurityConfigData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SecurityConfigData(
      id: serializer.fromJson<int>(json['id']),
      isLocked: serializer.fromJson<bool>(json['isLocked']),
      lastSeenTime: serializer.fromJson<DateTime>(json['lastSeenTime']),
      lastKnownGoodTime:
          serializer.fromJson<DateTime?>(json['lastKnownGoodTime']),
      monotonicLastSeen:
          serializer.fromJson<double?>(json['monotonicLastSeen']),
      offlineCredits: serializer.fromJson<int>(json['offlineCredits']),
      creditSpentIdsLocal:
          serializer.fromJson<String>(json['creditSpentIdsLocal']),
      creditServerCounter:
          serializer.fromJson<int>(json['creditServerCounter']),
      creditSpentBatchId:
          serializer.fromJson<String?>(json['creditSpentBatchId']),
      lastCreditRefillServerTime:
          serializer.fromJson<DateTime?>(json['lastCreditRefillServerTime']),
      lastPullTimestamp:
          serializer.fromJson<DateTime?>(json['lastPullTimestamp']),
      syncCursor: serializer.fromJson<String?>(json['syncCursor']),
      lastSyncAttemptTime:
          serializer.fromJson<DateTime?>(json['lastSyncAttemptTime']),
      syncCooldownUntil:
          serializer.fromJson<DateTime?>(json['syncCooldownUntil']),
      lastRealtimeEventId:
          serializer.fromJson<int>(json['lastRealtimeEventId']),
      heartbeatLastSuccess:
          serializer.fromJson<DateTime?>(json['heartbeatLastSuccess']),
      lastVacuumDate: serializer.fromJson<DateTime?>(json['lastVacuumDate']),
      encryptionKeyWrapped:
          serializer.fromJson<String?>(json['encryptionKeyWrapped']),
      encryptionRecoveryNeeded:
          serializer.fromJson<bool>(json['encryptionRecoveryNeeded']),
      corruptedRecordIds:
          serializer.fromJson<String>(json['corruptedRecordIds']),
      lastKnownPasswordHashVersion:
          serializer.fromJson<int>(json['lastKnownPasswordHashVersion']),
      sessionKeyEncrypted:
          serializer.fromJson<String?>(json['sessionKeyEncrypted']),
      sessionKeyExpiry:
          serializer.fromJson<DateTime?>(json['sessionKeyExpiry']),
      syncPendingAfterBiometricTimeout:
          serializer.fromJson<bool>(json['syncPendingAfterBiometricTimeout']),
      currentDeviceId: serializer.fromJson<String>(json['currentDeviceId']),
      pendingDbReplacement:
          serializer.fromJson<bool>(json['pendingDbReplacement']),
      vacuumedDbPath: serializer.fromJson<String?>(json['vacuumedDbPath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'isLocked': serializer.toJson<bool>(isLocked),
      'lastSeenTime': serializer.toJson<DateTime>(lastSeenTime),
      'lastKnownGoodTime': serializer.toJson<DateTime?>(lastKnownGoodTime),
      'monotonicLastSeen': serializer.toJson<double?>(monotonicLastSeen),
      'offlineCredits': serializer.toJson<int>(offlineCredits),
      'creditSpentIdsLocal': serializer.toJson<String>(creditSpentIdsLocal),
      'creditServerCounter': serializer.toJson<int>(creditServerCounter),
      'creditSpentBatchId': serializer.toJson<String?>(creditSpentBatchId),
      'lastCreditRefillServerTime':
          serializer.toJson<DateTime?>(lastCreditRefillServerTime),
      'lastPullTimestamp': serializer.toJson<DateTime?>(lastPullTimestamp),
      'syncCursor': serializer.toJson<String?>(syncCursor),
      'lastSyncAttemptTime': serializer.toJson<DateTime?>(lastSyncAttemptTime),
      'syncCooldownUntil': serializer.toJson<DateTime?>(syncCooldownUntil),
      'lastRealtimeEventId': serializer.toJson<int>(lastRealtimeEventId),
      'heartbeatLastSuccess':
          serializer.toJson<DateTime?>(heartbeatLastSuccess),
      'lastVacuumDate': serializer.toJson<DateTime?>(lastVacuumDate),
      'encryptionKeyWrapped': serializer.toJson<String?>(encryptionKeyWrapped),
      'encryptionRecoveryNeeded':
          serializer.toJson<bool>(encryptionRecoveryNeeded),
      'corruptedRecordIds': serializer.toJson<String>(corruptedRecordIds),
      'lastKnownPasswordHashVersion':
          serializer.toJson<int>(lastKnownPasswordHashVersion),
      'sessionKeyEncrypted': serializer.toJson<String?>(sessionKeyEncrypted),
      'sessionKeyExpiry': serializer.toJson<DateTime?>(sessionKeyExpiry),
      'syncPendingAfterBiometricTimeout':
          serializer.toJson<bool>(syncPendingAfterBiometricTimeout),
      'currentDeviceId': serializer.toJson<String>(currentDeviceId),
      'pendingDbReplacement': serializer.toJson<bool>(pendingDbReplacement),
      'vacuumedDbPath': serializer.toJson<String?>(vacuumedDbPath),
    };
  }

  SecurityConfigData copyWith(
          {int? id,
          bool? isLocked,
          DateTime? lastSeenTime,
          Value<DateTime?> lastKnownGoodTime = const Value.absent(),
          Value<double?> monotonicLastSeen = const Value.absent(),
          int? offlineCredits,
          String? creditSpentIdsLocal,
          int? creditServerCounter,
          Value<String?> creditSpentBatchId = const Value.absent(),
          Value<DateTime?> lastCreditRefillServerTime = const Value.absent(),
          Value<DateTime?> lastPullTimestamp = const Value.absent(),
          Value<String?> syncCursor = const Value.absent(),
          Value<DateTime?> lastSyncAttemptTime = const Value.absent(),
          Value<DateTime?> syncCooldownUntil = const Value.absent(),
          int? lastRealtimeEventId,
          Value<DateTime?> heartbeatLastSuccess = const Value.absent(),
          Value<DateTime?> lastVacuumDate = const Value.absent(),
          Value<String?> encryptionKeyWrapped = const Value.absent(),
          bool? encryptionRecoveryNeeded,
          String? corruptedRecordIds,
          int? lastKnownPasswordHashVersion,
          Value<String?> sessionKeyEncrypted = const Value.absent(),
          Value<DateTime?> sessionKeyExpiry = const Value.absent(),
          bool? syncPendingAfterBiometricTimeout,
          String? currentDeviceId,
          bool? pendingDbReplacement,
          Value<String?> vacuumedDbPath = const Value.absent()}) =>
      SecurityConfigData(
        id: id ?? this.id,
        isLocked: isLocked ?? this.isLocked,
        lastSeenTime: lastSeenTime ?? this.lastSeenTime,
        lastKnownGoodTime: lastKnownGoodTime.present
            ? lastKnownGoodTime.value
            : this.lastKnownGoodTime,
        monotonicLastSeen: monotonicLastSeen.present
            ? monotonicLastSeen.value
            : this.monotonicLastSeen,
        offlineCredits: offlineCredits ?? this.offlineCredits,
        creditSpentIdsLocal: creditSpentIdsLocal ?? this.creditSpentIdsLocal,
        creditServerCounter: creditServerCounter ?? this.creditServerCounter,
        creditSpentBatchId: creditSpentBatchId.present
            ? creditSpentBatchId.value
            : this.creditSpentBatchId,
        lastCreditRefillServerTime: lastCreditRefillServerTime.present
            ? lastCreditRefillServerTime.value
            : this.lastCreditRefillServerTime,
        lastPullTimestamp: lastPullTimestamp.present
            ? lastPullTimestamp.value
            : this.lastPullTimestamp,
        syncCursor: syncCursor.present ? syncCursor.value : this.syncCursor,
        lastSyncAttemptTime: lastSyncAttemptTime.present
            ? lastSyncAttemptTime.value
            : this.lastSyncAttemptTime,
        syncCooldownUntil: syncCooldownUntil.present
            ? syncCooldownUntil.value
            : this.syncCooldownUntil,
        lastRealtimeEventId: lastRealtimeEventId ?? this.lastRealtimeEventId,
        heartbeatLastSuccess: heartbeatLastSuccess.present
            ? heartbeatLastSuccess.value
            : this.heartbeatLastSuccess,
        lastVacuumDate:
            lastVacuumDate.present ? lastVacuumDate.value : this.lastVacuumDate,
        encryptionKeyWrapped: encryptionKeyWrapped.present
            ? encryptionKeyWrapped.value
            : this.encryptionKeyWrapped,
        encryptionRecoveryNeeded:
            encryptionRecoveryNeeded ?? this.encryptionRecoveryNeeded,
        corruptedRecordIds: corruptedRecordIds ?? this.corruptedRecordIds,
        lastKnownPasswordHashVersion:
            lastKnownPasswordHashVersion ?? this.lastKnownPasswordHashVersion,
        sessionKeyEncrypted: sessionKeyEncrypted.present
            ? sessionKeyEncrypted.value
            : this.sessionKeyEncrypted,
        sessionKeyExpiry: sessionKeyExpiry.present
            ? sessionKeyExpiry.value
            : this.sessionKeyExpiry,
        syncPendingAfterBiometricTimeout: syncPendingAfterBiometricTimeout ??
            this.syncPendingAfterBiometricTimeout,
        currentDeviceId: currentDeviceId ?? this.currentDeviceId,
        pendingDbReplacement: pendingDbReplacement ?? this.pendingDbReplacement,
        vacuumedDbPath:
            vacuumedDbPath.present ? vacuumedDbPath.value : this.vacuumedDbPath,
      );
  SecurityConfigData copyWithCompanion(SecurityConfigCompanion data) {
    return SecurityConfigData(
      id: data.id.present ? data.id.value : this.id,
      isLocked: data.isLocked.present ? data.isLocked.value : this.isLocked,
      lastSeenTime: data.lastSeenTime.present
          ? data.lastSeenTime.value
          : this.lastSeenTime,
      lastKnownGoodTime: data.lastKnownGoodTime.present
          ? data.lastKnownGoodTime.value
          : this.lastKnownGoodTime,
      monotonicLastSeen: data.monotonicLastSeen.present
          ? data.monotonicLastSeen.value
          : this.monotonicLastSeen,
      offlineCredits: data.offlineCredits.present
          ? data.offlineCredits.value
          : this.offlineCredits,
      creditSpentIdsLocal: data.creditSpentIdsLocal.present
          ? data.creditSpentIdsLocal.value
          : this.creditSpentIdsLocal,
      creditServerCounter: data.creditServerCounter.present
          ? data.creditServerCounter.value
          : this.creditServerCounter,
      creditSpentBatchId: data.creditSpentBatchId.present
          ? data.creditSpentBatchId.value
          : this.creditSpentBatchId,
      lastCreditRefillServerTime: data.lastCreditRefillServerTime.present
          ? data.lastCreditRefillServerTime.value
          : this.lastCreditRefillServerTime,
      lastPullTimestamp: data.lastPullTimestamp.present
          ? data.lastPullTimestamp.value
          : this.lastPullTimestamp,
      syncCursor:
          data.syncCursor.present ? data.syncCursor.value : this.syncCursor,
      lastSyncAttemptTime: data.lastSyncAttemptTime.present
          ? data.lastSyncAttemptTime.value
          : this.lastSyncAttemptTime,
      syncCooldownUntil: data.syncCooldownUntil.present
          ? data.syncCooldownUntil.value
          : this.syncCooldownUntil,
      lastRealtimeEventId: data.lastRealtimeEventId.present
          ? data.lastRealtimeEventId.value
          : this.lastRealtimeEventId,
      heartbeatLastSuccess: data.heartbeatLastSuccess.present
          ? data.heartbeatLastSuccess.value
          : this.heartbeatLastSuccess,
      lastVacuumDate: data.lastVacuumDate.present
          ? data.lastVacuumDate.value
          : this.lastVacuumDate,
      encryptionKeyWrapped: data.encryptionKeyWrapped.present
          ? data.encryptionKeyWrapped.value
          : this.encryptionKeyWrapped,
      encryptionRecoveryNeeded: data.encryptionRecoveryNeeded.present
          ? data.encryptionRecoveryNeeded.value
          : this.encryptionRecoveryNeeded,
      corruptedRecordIds: data.corruptedRecordIds.present
          ? data.corruptedRecordIds.value
          : this.corruptedRecordIds,
      lastKnownPasswordHashVersion: data.lastKnownPasswordHashVersion.present
          ? data.lastKnownPasswordHashVersion.value
          : this.lastKnownPasswordHashVersion,
      sessionKeyEncrypted: data.sessionKeyEncrypted.present
          ? data.sessionKeyEncrypted.value
          : this.sessionKeyEncrypted,
      sessionKeyExpiry: data.sessionKeyExpiry.present
          ? data.sessionKeyExpiry.value
          : this.sessionKeyExpiry,
      syncPendingAfterBiometricTimeout:
          data.syncPendingAfterBiometricTimeout.present
              ? data.syncPendingAfterBiometricTimeout.value
              : this.syncPendingAfterBiometricTimeout,
      currentDeviceId: data.currentDeviceId.present
          ? data.currentDeviceId.value
          : this.currentDeviceId,
      pendingDbReplacement: data.pendingDbReplacement.present
          ? data.pendingDbReplacement.value
          : this.pendingDbReplacement,
      vacuumedDbPath: data.vacuumedDbPath.present
          ? data.vacuumedDbPath.value
          : this.vacuumedDbPath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SecurityConfigData(')
          ..write('id: $id, ')
          ..write('isLocked: $isLocked, ')
          ..write('lastSeenTime: $lastSeenTime, ')
          ..write('lastKnownGoodTime: $lastKnownGoodTime, ')
          ..write('monotonicLastSeen: $monotonicLastSeen, ')
          ..write('offlineCredits: $offlineCredits, ')
          ..write('creditSpentIdsLocal: $creditSpentIdsLocal, ')
          ..write('creditServerCounter: $creditServerCounter, ')
          ..write('creditSpentBatchId: $creditSpentBatchId, ')
          ..write('lastCreditRefillServerTime: $lastCreditRefillServerTime, ')
          ..write('lastPullTimestamp: $lastPullTimestamp, ')
          ..write('syncCursor: $syncCursor, ')
          ..write('lastSyncAttemptTime: $lastSyncAttemptTime, ')
          ..write('syncCooldownUntil: $syncCooldownUntil, ')
          ..write('lastRealtimeEventId: $lastRealtimeEventId, ')
          ..write('heartbeatLastSuccess: $heartbeatLastSuccess, ')
          ..write('lastVacuumDate: $lastVacuumDate, ')
          ..write('encryptionKeyWrapped: $encryptionKeyWrapped, ')
          ..write('encryptionRecoveryNeeded: $encryptionRecoveryNeeded, ')
          ..write('corruptedRecordIds: $corruptedRecordIds, ')
          ..write(
              'lastKnownPasswordHashVersion: $lastKnownPasswordHashVersion, ')
          ..write('sessionKeyEncrypted: $sessionKeyEncrypted, ')
          ..write('sessionKeyExpiry: $sessionKeyExpiry, ')
          ..write(
              'syncPendingAfterBiometricTimeout: $syncPendingAfterBiometricTimeout, ')
          ..write('currentDeviceId: $currentDeviceId, ')
          ..write('pendingDbReplacement: $pendingDbReplacement, ')
          ..write('vacuumedDbPath: $vacuumedDbPath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        isLocked,
        lastSeenTime,
        lastKnownGoodTime,
        monotonicLastSeen,
        offlineCredits,
        creditSpentIdsLocal,
        creditServerCounter,
        creditSpentBatchId,
        lastCreditRefillServerTime,
        lastPullTimestamp,
        syncCursor,
        lastSyncAttemptTime,
        syncCooldownUntil,
        lastRealtimeEventId,
        heartbeatLastSuccess,
        lastVacuumDate,
        encryptionKeyWrapped,
        encryptionRecoveryNeeded,
        corruptedRecordIds,
        lastKnownPasswordHashVersion,
        sessionKeyEncrypted,
        sessionKeyExpiry,
        syncPendingAfterBiometricTimeout,
        currentDeviceId,
        pendingDbReplacement,
        vacuumedDbPath
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SecurityConfigData &&
          other.id == this.id &&
          other.isLocked == this.isLocked &&
          other.lastSeenTime == this.lastSeenTime &&
          other.lastKnownGoodTime == this.lastKnownGoodTime &&
          other.monotonicLastSeen == this.monotonicLastSeen &&
          other.offlineCredits == this.offlineCredits &&
          other.creditSpentIdsLocal == this.creditSpentIdsLocal &&
          other.creditServerCounter == this.creditServerCounter &&
          other.creditSpentBatchId == this.creditSpentBatchId &&
          other.lastCreditRefillServerTime == this.lastCreditRefillServerTime &&
          other.lastPullTimestamp == this.lastPullTimestamp &&
          other.syncCursor == this.syncCursor &&
          other.lastSyncAttemptTime == this.lastSyncAttemptTime &&
          other.syncCooldownUntil == this.syncCooldownUntil &&
          other.lastRealtimeEventId == this.lastRealtimeEventId &&
          other.heartbeatLastSuccess == this.heartbeatLastSuccess &&
          other.lastVacuumDate == this.lastVacuumDate &&
          other.encryptionKeyWrapped == this.encryptionKeyWrapped &&
          other.encryptionRecoveryNeeded == this.encryptionRecoveryNeeded &&
          other.corruptedRecordIds == this.corruptedRecordIds &&
          other.lastKnownPasswordHashVersion ==
              this.lastKnownPasswordHashVersion &&
          other.sessionKeyEncrypted == this.sessionKeyEncrypted &&
          other.sessionKeyExpiry == this.sessionKeyExpiry &&
          other.syncPendingAfterBiometricTimeout ==
              this.syncPendingAfterBiometricTimeout &&
          other.currentDeviceId == this.currentDeviceId &&
          other.pendingDbReplacement == this.pendingDbReplacement &&
          other.vacuumedDbPath == this.vacuumedDbPath);
}

class SecurityConfigCompanion extends UpdateCompanion<SecurityConfigData> {
  final Value<int> id;
  final Value<bool> isLocked;
  final Value<DateTime> lastSeenTime;
  final Value<DateTime?> lastKnownGoodTime;
  final Value<double?> monotonicLastSeen;
  final Value<int> offlineCredits;
  final Value<String> creditSpentIdsLocal;
  final Value<int> creditServerCounter;
  final Value<String?> creditSpentBatchId;
  final Value<DateTime?> lastCreditRefillServerTime;
  final Value<DateTime?> lastPullTimestamp;
  final Value<String?> syncCursor;
  final Value<DateTime?> lastSyncAttemptTime;
  final Value<DateTime?> syncCooldownUntil;
  final Value<int> lastRealtimeEventId;
  final Value<DateTime?> heartbeatLastSuccess;
  final Value<DateTime?> lastVacuumDate;
  final Value<String?> encryptionKeyWrapped;
  final Value<bool> encryptionRecoveryNeeded;
  final Value<String> corruptedRecordIds;
  final Value<int> lastKnownPasswordHashVersion;
  final Value<String?> sessionKeyEncrypted;
  final Value<DateTime?> sessionKeyExpiry;
  final Value<bool> syncPendingAfterBiometricTimeout;
  final Value<String> currentDeviceId;
  final Value<bool> pendingDbReplacement;
  final Value<String?> vacuumedDbPath;
  const SecurityConfigCompanion({
    this.id = const Value.absent(),
    this.isLocked = const Value.absent(),
    this.lastSeenTime = const Value.absent(),
    this.lastKnownGoodTime = const Value.absent(),
    this.monotonicLastSeen = const Value.absent(),
    this.offlineCredits = const Value.absent(),
    this.creditSpentIdsLocal = const Value.absent(),
    this.creditServerCounter = const Value.absent(),
    this.creditSpentBatchId = const Value.absent(),
    this.lastCreditRefillServerTime = const Value.absent(),
    this.lastPullTimestamp = const Value.absent(),
    this.syncCursor = const Value.absent(),
    this.lastSyncAttemptTime = const Value.absent(),
    this.syncCooldownUntil = const Value.absent(),
    this.lastRealtimeEventId = const Value.absent(),
    this.heartbeatLastSuccess = const Value.absent(),
    this.lastVacuumDate = const Value.absent(),
    this.encryptionKeyWrapped = const Value.absent(),
    this.encryptionRecoveryNeeded = const Value.absent(),
    this.corruptedRecordIds = const Value.absent(),
    this.lastKnownPasswordHashVersion = const Value.absent(),
    this.sessionKeyEncrypted = const Value.absent(),
    this.sessionKeyExpiry = const Value.absent(),
    this.syncPendingAfterBiometricTimeout = const Value.absent(),
    this.currentDeviceId = const Value.absent(),
    this.pendingDbReplacement = const Value.absent(),
    this.vacuumedDbPath = const Value.absent(),
  });
  SecurityConfigCompanion.insert({
    this.id = const Value.absent(),
    this.isLocked = const Value.absent(),
    this.lastSeenTime = const Value.absent(),
    this.lastKnownGoodTime = const Value.absent(),
    this.monotonicLastSeen = const Value.absent(),
    this.offlineCredits = const Value.absent(),
    this.creditSpentIdsLocal = const Value.absent(),
    this.creditServerCounter = const Value.absent(),
    this.creditSpentBatchId = const Value.absent(),
    this.lastCreditRefillServerTime = const Value.absent(),
    this.lastPullTimestamp = const Value.absent(),
    this.syncCursor = const Value.absent(),
    this.lastSyncAttemptTime = const Value.absent(),
    this.syncCooldownUntil = const Value.absent(),
    this.lastRealtimeEventId = const Value.absent(),
    this.heartbeatLastSuccess = const Value.absent(),
    this.lastVacuumDate = const Value.absent(),
    this.encryptionKeyWrapped = const Value.absent(),
    this.encryptionRecoveryNeeded = const Value.absent(),
    this.corruptedRecordIds = const Value.absent(),
    this.lastKnownPasswordHashVersion = const Value.absent(),
    this.sessionKeyEncrypted = const Value.absent(),
    this.sessionKeyExpiry = const Value.absent(),
    this.syncPendingAfterBiometricTimeout = const Value.absent(),
    required String currentDeviceId,
    this.pendingDbReplacement = const Value.absent(),
    this.vacuumedDbPath = const Value.absent(),
  }) : currentDeviceId = Value(currentDeviceId);
  static Insertable<SecurityConfigData> custom({
    Expression<int>? id,
    Expression<bool>? isLocked,
    Expression<DateTime>? lastSeenTime,
    Expression<DateTime>? lastKnownGoodTime,
    Expression<double>? monotonicLastSeen,
    Expression<int>? offlineCredits,
    Expression<String>? creditSpentIdsLocal,
    Expression<int>? creditServerCounter,
    Expression<String>? creditSpentBatchId,
    Expression<DateTime>? lastCreditRefillServerTime,
    Expression<DateTime>? lastPullTimestamp,
    Expression<String>? syncCursor,
    Expression<DateTime>? lastSyncAttemptTime,
    Expression<DateTime>? syncCooldownUntil,
    Expression<int>? lastRealtimeEventId,
    Expression<DateTime>? heartbeatLastSuccess,
    Expression<DateTime>? lastVacuumDate,
    Expression<String>? encryptionKeyWrapped,
    Expression<bool>? encryptionRecoveryNeeded,
    Expression<String>? corruptedRecordIds,
    Expression<int>? lastKnownPasswordHashVersion,
    Expression<String>? sessionKeyEncrypted,
    Expression<DateTime>? sessionKeyExpiry,
    Expression<bool>? syncPendingAfterBiometricTimeout,
    Expression<String>? currentDeviceId,
    Expression<bool>? pendingDbReplacement,
    Expression<String>? vacuumedDbPath,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (isLocked != null) 'is_locked': isLocked,
      if (lastSeenTime != null) 'last_seen_time': lastSeenTime,
      if (lastKnownGoodTime != null) 'last_known_good_time': lastKnownGoodTime,
      if (monotonicLastSeen != null) 'monotonic_last_seen': monotonicLastSeen,
      if (offlineCredits != null) 'offline_credits': offlineCredits,
      if (creditSpentIdsLocal != null)
        'credit_spent_ids_local': creditSpentIdsLocal,
      if (creditServerCounter != null)
        'credit_server_counter': creditServerCounter,
      if (creditSpentBatchId != null)
        'credit_spent_batch_id': creditSpentBatchId,
      if (lastCreditRefillServerTime != null)
        'last_credit_refill_server_time': lastCreditRefillServerTime,
      if (lastPullTimestamp != null) 'last_pull_timestamp': lastPullTimestamp,
      if (syncCursor != null) 'sync_cursor': syncCursor,
      if (lastSyncAttemptTime != null)
        'last_sync_attempt_time': lastSyncAttemptTime,
      if (syncCooldownUntil != null) 'sync_cooldown_until': syncCooldownUntil,
      if (lastRealtimeEventId != null)
        'last_realtime_event_id': lastRealtimeEventId,
      if (heartbeatLastSuccess != null)
        'heartbeat_last_success': heartbeatLastSuccess,
      if (lastVacuumDate != null) 'last_vacuum_date': lastVacuumDate,
      if (encryptionKeyWrapped != null)
        'encryption_key_wrapped': encryptionKeyWrapped,
      if (encryptionRecoveryNeeded != null)
        'encryption_recovery_needed': encryptionRecoveryNeeded,
      if (corruptedRecordIds != null)
        'corrupted_record_ids': corruptedRecordIds,
      if (lastKnownPasswordHashVersion != null)
        'last_known_password_hash_version': lastKnownPasswordHashVersion,
      if (sessionKeyEncrypted != null)
        'session_key_encrypted': sessionKeyEncrypted,
      if (sessionKeyExpiry != null) 'session_key_expiry': sessionKeyExpiry,
      if (syncPendingAfterBiometricTimeout != null)
        'sync_pending_after_biometric_timeout':
            syncPendingAfterBiometricTimeout,
      if (currentDeviceId != null) 'current_device_id': currentDeviceId,
      if (pendingDbReplacement != null)
        'pending_db_replacement': pendingDbReplacement,
      if (vacuumedDbPath != null) 'vacuumed_db_path': vacuumedDbPath,
    });
  }

  SecurityConfigCompanion copyWith(
      {Value<int>? id,
      Value<bool>? isLocked,
      Value<DateTime>? lastSeenTime,
      Value<DateTime?>? lastKnownGoodTime,
      Value<double?>? monotonicLastSeen,
      Value<int>? offlineCredits,
      Value<String>? creditSpentIdsLocal,
      Value<int>? creditServerCounter,
      Value<String?>? creditSpentBatchId,
      Value<DateTime?>? lastCreditRefillServerTime,
      Value<DateTime?>? lastPullTimestamp,
      Value<String?>? syncCursor,
      Value<DateTime?>? lastSyncAttemptTime,
      Value<DateTime?>? syncCooldownUntil,
      Value<int>? lastRealtimeEventId,
      Value<DateTime?>? heartbeatLastSuccess,
      Value<DateTime?>? lastVacuumDate,
      Value<String?>? encryptionKeyWrapped,
      Value<bool>? encryptionRecoveryNeeded,
      Value<String>? corruptedRecordIds,
      Value<int>? lastKnownPasswordHashVersion,
      Value<String?>? sessionKeyEncrypted,
      Value<DateTime?>? sessionKeyExpiry,
      Value<bool>? syncPendingAfterBiometricTimeout,
      Value<String>? currentDeviceId,
      Value<bool>? pendingDbReplacement,
      Value<String?>? vacuumedDbPath}) {
    return SecurityConfigCompanion(
      id: id ?? this.id,
      isLocked: isLocked ?? this.isLocked,
      lastSeenTime: lastSeenTime ?? this.lastSeenTime,
      lastKnownGoodTime: lastKnownGoodTime ?? this.lastKnownGoodTime,
      monotonicLastSeen: monotonicLastSeen ?? this.monotonicLastSeen,
      offlineCredits: offlineCredits ?? this.offlineCredits,
      creditSpentIdsLocal: creditSpentIdsLocal ?? this.creditSpentIdsLocal,
      creditServerCounter: creditServerCounter ?? this.creditServerCounter,
      creditSpentBatchId: creditSpentBatchId ?? this.creditSpentBatchId,
      lastCreditRefillServerTime:
          lastCreditRefillServerTime ?? this.lastCreditRefillServerTime,
      lastPullTimestamp: lastPullTimestamp ?? this.lastPullTimestamp,
      syncCursor: syncCursor ?? this.syncCursor,
      lastSyncAttemptTime: lastSyncAttemptTime ?? this.lastSyncAttemptTime,
      syncCooldownUntil: syncCooldownUntil ?? this.syncCooldownUntil,
      lastRealtimeEventId: lastRealtimeEventId ?? this.lastRealtimeEventId,
      heartbeatLastSuccess: heartbeatLastSuccess ?? this.heartbeatLastSuccess,
      lastVacuumDate: lastVacuumDate ?? this.lastVacuumDate,
      encryptionKeyWrapped: encryptionKeyWrapped ?? this.encryptionKeyWrapped,
      encryptionRecoveryNeeded:
          encryptionRecoveryNeeded ?? this.encryptionRecoveryNeeded,
      corruptedRecordIds: corruptedRecordIds ?? this.corruptedRecordIds,
      lastKnownPasswordHashVersion:
          lastKnownPasswordHashVersion ?? this.lastKnownPasswordHashVersion,
      sessionKeyEncrypted: sessionKeyEncrypted ?? this.sessionKeyEncrypted,
      sessionKeyExpiry: sessionKeyExpiry ?? this.sessionKeyExpiry,
      syncPendingAfterBiometricTimeout: syncPendingAfterBiometricTimeout ??
          this.syncPendingAfterBiometricTimeout,
      currentDeviceId: currentDeviceId ?? this.currentDeviceId,
      pendingDbReplacement: pendingDbReplacement ?? this.pendingDbReplacement,
      vacuumedDbPath: vacuumedDbPath ?? this.vacuumedDbPath,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (isLocked.present) {
      map['is_locked'] = Variable<bool>(isLocked.value);
    }
    if (lastSeenTime.present) {
      map['last_seen_time'] = Variable<DateTime>(lastSeenTime.value);
    }
    if (lastKnownGoodTime.present) {
      map['last_known_good_time'] = Variable<DateTime>(lastKnownGoodTime.value);
    }
    if (monotonicLastSeen.present) {
      map['monotonic_last_seen'] = Variable<double>(monotonicLastSeen.value);
    }
    if (offlineCredits.present) {
      map['offline_credits'] = Variable<int>(offlineCredits.value);
    }
    if (creditSpentIdsLocal.present) {
      map['credit_spent_ids_local'] =
          Variable<String>(creditSpentIdsLocal.value);
    }
    if (creditServerCounter.present) {
      map['credit_server_counter'] = Variable<int>(creditServerCounter.value);
    }
    if (creditSpentBatchId.present) {
      map['credit_spent_batch_id'] = Variable<String>(creditSpentBatchId.value);
    }
    if (lastCreditRefillServerTime.present) {
      map['last_credit_refill_server_time'] =
          Variable<DateTime>(lastCreditRefillServerTime.value);
    }
    if (lastPullTimestamp.present) {
      map['last_pull_timestamp'] = Variable<DateTime>(lastPullTimestamp.value);
    }
    if (syncCursor.present) {
      map['sync_cursor'] = Variable<String>(syncCursor.value);
    }
    if (lastSyncAttemptTime.present) {
      map['last_sync_attempt_time'] =
          Variable<DateTime>(lastSyncAttemptTime.value);
    }
    if (syncCooldownUntil.present) {
      map['sync_cooldown_until'] = Variable<DateTime>(syncCooldownUntil.value);
    }
    if (lastRealtimeEventId.present) {
      map['last_realtime_event_id'] = Variable<int>(lastRealtimeEventId.value);
    }
    if (heartbeatLastSuccess.present) {
      map['heartbeat_last_success'] =
          Variable<DateTime>(heartbeatLastSuccess.value);
    }
    if (lastVacuumDate.present) {
      map['last_vacuum_date'] = Variable<DateTime>(lastVacuumDate.value);
    }
    if (encryptionKeyWrapped.present) {
      map['encryption_key_wrapped'] =
          Variable<String>(encryptionKeyWrapped.value);
    }
    if (encryptionRecoveryNeeded.present) {
      map['encryption_recovery_needed'] =
          Variable<bool>(encryptionRecoveryNeeded.value);
    }
    if (corruptedRecordIds.present) {
      map['corrupted_record_ids'] = Variable<String>(corruptedRecordIds.value);
    }
    if (lastKnownPasswordHashVersion.present) {
      map['last_known_password_hash_version'] =
          Variable<int>(lastKnownPasswordHashVersion.value);
    }
    if (sessionKeyEncrypted.present) {
      map['session_key_encrypted'] =
          Variable<String>(sessionKeyEncrypted.value);
    }
    if (sessionKeyExpiry.present) {
      map['session_key_expiry'] = Variable<DateTime>(sessionKeyExpiry.value);
    }
    if (syncPendingAfterBiometricTimeout.present) {
      map['sync_pending_after_biometric_timeout'] =
          Variable<bool>(syncPendingAfterBiometricTimeout.value);
    }
    if (currentDeviceId.present) {
      map['current_device_id'] = Variable<String>(currentDeviceId.value);
    }
    if (pendingDbReplacement.present) {
      map['pending_db_replacement'] =
          Variable<bool>(pendingDbReplacement.value);
    }
    if (vacuumedDbPath.present) {
      map['vacuumed_db_path'] = Variable<String>(vacuumedDbPath.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SecurityConfigCompanion(')
          ..write('id: $id, ')
          ..write('isLocked: $isLocked, ')
          ..write('lastSeenTime: $lastSeenTime, ')
          ..write('lastKnownGoodTime: $lastKnownGoodTime, ')
          ..write('monotonicLastSeen: $monotonicLastSeen, ')
          ..write('offlineCredits: $offlineCredits, ')
          ..write('creditSpentIdsLocal: $creditSpentIdsLocal, ')
          ..write('creditServerCounter: $creditServerCounter, ')
          ..write('creditSpentBatchId: $creditSpentBatchId, ')
          ..write('lastCreditRefillServerTime: $lastCreditRefillServerTime, ')
          ..write('lastPullTimestamp: $lastPullTimestamp, ')
          ..write('syncCursor: $syncCursor, ')
          ..write('lastSyncAttemptTime: $lastSyncAttemptTime, ')
          ..write('syncCooldownUntil: $syncCooldownUntil, ')
          ..write('lastRealtimeEventId: $lastRealtimeEventId, ')
          ..write('heartbeatLastSuccess: $heartbeatLastSuccess, ')
          ..write('lastVacuumDate: $lastVacuumDate, ')
          ..write('encryptionKeyWrapped: $encryptionKeyWrapped, ')
          ..write('encryptionRecoveryNeeded: $encryptionRecoveryNeeded, ')
          ..write('corruptedRecordIds: $corruptedRecordIds, ')
          ..write(
              'lastKnownPasswordHashVersion: $lastKnownPasswordHashVersion, ')
          ..write('sessionKeyEncrypted: $sessionKeyEncrypted, ')
          ..write('sessionKeyExpiry: $sessionKeyExpiry, ')
          ..write(
              'syncPendingAfterBiometricTimeout: $syncPendingAfterBiometricTimeout, ')
          ..write('currentDeviceId: $currentDeviceId, ')
          ..write('pendingDbReplacement: $pendingDbReplacement, ')
          ..write('vacuumedDbPath: $vacuumedDbPath')
          ..write(')'))
        .toString();
  }
}

class $SyncQueueTable extends SyncQueue
    with TableInfo<$SyncQueueTable, SyncQueueData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _queueTableMeta =
      const VerificationMeta('queueTable');
  @override
  late final GeneratedColumn<String> queueTable = GeneratedColumn<String>(
      'queue_table', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recordLocalIdMeta =
      const VerificationMeta('recordLocalId');
  @override
  late final GeneratedColumn<int> recordLocalId = GeneratedColumn<int>(
      'record_local_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _operationMeta =
      const VerificationMeta('operation');
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
      'operation', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _attemptsMeta =
      const VerificationMeta('attempts');
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
      'attempts', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isEmergencyMeta =
      const VerificationMeta('isEmergency');
  @override
  late final GeneratedColumn<bool> isEmergency = GeneratedColumn<bool>(
      'is_emergency', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_emergency" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _lastAttemptAtMeta =
      const VerificationMeta('lastAttemptAt');
  @override
  late final GeneratedColumn<DateTime> lastAttemptAt =
      GeneratedColumn<DateTime>('last_attempt_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        queueTable,
        recordLocalId,
        operation,
        payload,
        attempts,
        isEmergency,
        createdAt,
        lastAttemptAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_queue';
  @override
  VerificationContext validateIntegrity(Insertable<SyncQueueData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('queue_table')) {
      context.handle(
          _queueTableMeta,
          queueTable.isAcceptableOrUnknown(
              data['queue_table']!, _queueTableMeta));
    } else if (isInserting) {
      context.missing(_queueTableMeta);
    }
    if (data.containsKey('record_local_id')) {
      context.handle(
          _recordLocalIdMeta,
          recordLocalId.isAcceptableOrUnknown(
              data['record_local_id']!, _recordLocalIdMeta));
    } else if (isInserting) {
      context.missing(_recordLocalIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(_operationMeta,
          operation.isAcceptableOrUnknown(data['operation']!, _operationMeta));
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(_attemptsMeta,
          attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta));
    }
    if (data.containsKey('is_emergency')) {
      context.handle(
          _isEmergencyMeta,
          isEmergency.isAcceptableOrUnknown(
              data['is_emergency']!, _isEmergencyMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
          _lastAttemptAtMeta,
          lastAttemptAt.isAcceptableOrUnknown(
              data['last_attempt_at']!, _lastAttemptAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncQueueData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncQueueData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      queueTable: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}queue_table'])!,
      recordLocalId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}record_local_id'])!,
      operation: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}operation'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      attempts: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempts'])!,
      isEmergency: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_emergency'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      lastAttemptAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_attempt_at']),
    );
  }

  @override
  $SyncQueueTable createAlias(String alias) {
    return $SyncQueueTable(attachedDatabase, alias);
  }
}

class SyncQueueData extends DataClass implements Insertable<SyncQueueData> {
  final int id;
  final String queueTable;
  final int recordLocalId;
  final String operation;
  final String payload;
  final int attempts;
  final bool isEmergency;
  final DateTime createdAt;
  final DateTime? lastAttemptAt;
  const SyncQueueData(
      {required this.id,
      required this.queueTable,
      required this.recordLocalId,
      required this.operation,
      required this.payload,
      required this.attempts,
      required this.isEmergency,
      required this.createdAt,
      this.lastAttemptAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['queue_table'] = Variable<String>(queueTable);
    map['record_local_id'] = Variable<int>(recordLocalId);
    map['operation'] = Variable<String>(operation);
    map['payload'] = Variable<String>(payload);
    map['attempts'] = Variable<int>(attempts);
    map['is_emergency'] = Variable<bool>(isEmergency);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt);
    }
    return map;
  }

  SyncQueueCompanion toCompanion(bool nullToAbsent) {
    return SyncQueueCompanion(
      id: Value(id),
      queueTable: Value(queueTable),
      recordLocalId: Value(recordLocalId),
      operation: Value(operation),
      payload: Value(payload),
      attempts: Value(attempts),
      isEmergency: Value(isEmergency),
      createdAt: Value(createdAt),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
    );
  }

  factory SyncQueueData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncQueueData(
      id: serializer.fromJson<int>(json['id']),
      queueTable: serializer.fromJson<String>(json['queueTable']),
      recordLocalId: serializer.fromJson<int>(json['recordLocalId']),
      operation: serializer.fromJson<String>(json['operation']),
      payload: serializer.fromJson<String>(json['payload']),
      attempts: serializer.fromJson<int>(json['attempts']),
      isEmergency: serializer.fromJson<bool>(json['isEmergency']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastAttemptAt: serializer.fromJson<DateTime?>(json['lastAttemptAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'queueTable': serializer.toJson<String>(queueTable),
      'recordLocalId': serializer.toJson<int>(recordLocalId),
      'operation': serializer.toJson<String>(operation),
      'payload': serializer.toJson<String>(payload),
      'attempts': serializer.toJson<int>(attempts),
      'isEmergency': serializer.toJson<bool>(isEmergency),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastAttemptAt': serializer.toJson<DateTime?>(lastAttemptAt),
    };
  }

  SyncQueueData copyWith(
          {int? id,
          String? queueTable,
          int? recordLocalId,
          String? operation,
          String? payload,
          int? attempts,
          bool? isEmergency,
          DateTime? createdAt,
          Value<DateTime?> lastAttemptAt = const Value.absent()}) =>
      SyncQueueData(
        id: id ?? this.id,
        queueTable: queueTable ?? this.queueTable,
        recordLocalId: recordLocalId ?? this.recordLocalId,
        operation: operation ?? this.operation,
        payload: payload ?? this.payload,
        attempts: attempts ?? this.attempts,
        isEmergency: isEmergency ?? this.isEmergency,
        createdAt: createdAt ?? this.createdAt,
        lastAttemptAt:
            lastAttemptAt.present ? lastAttemptAt.value : this.lastAttemptAt,
      );
  SyncQueueData copyWithCompanion(SyncQueueCompanion data) {
    return SyncQueueData(
      id: data.id.present ? data.id.value : this.id,
      queueTable:
          data.queueTable.present ? data.queueTable.value : this.queueTable,
      recordLocalId: data.recordLocalId.present
          ? data.recordLocalId.value
          : this.recordLocalId,
      operation: data.operation.present ? data.operation.value : this.operation,
      payload: data.payload.present ? data.payload.value : this.payload,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      isEmergency:
          data.isEmergency.present ? data.isEmergency.value : this.isEmergency,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueData(')
          ..write('id: $id, ')
          ..write('queueTable: $queueTable, ')
          ..write('recordLocalId: $recordLocalId, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('attempts: $attempts, ')
          ..write('isEmergency: $isEmergency, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptAt: $lastAttemptAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, queueTable, recordLocalId, operation,
      payload, attempts, isEmergency, createdAt, lastAttemptAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncQueueData &&
          other.id == this.id &&
          other.queueTable == this.queueTable &&
          other.recordLocalId == this.recordLocalId &&
          other.operation == this.operation &&
          other.payload == this.payload &&
          other.attempts == this.attempts &&
          other.isEmergency == this.isEmergency &&
          other.createdAt == this.createdAt &&
          other.lastAttemptAt == this.lastAttemptAt);
}

class SyncQueueCompanion extends UpdateCompanion<SyncQueueData> {
  final Value<int> id;
  final Value<String> queueTable;
  final Value<int> recordLocalId;
  final Value<String> operation;
  final Value<String> payload;
  final Value<int> attempts;
  final Value<bool> isEmergency;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastAttemptAt;
  const SyncQueueCompanion({
    this.id = const Value.absent(),
    this.queueTable = const Value.absent(),
    this.recordLocalId = const Value.absent(),
    this.operation = const Value.absent(),
    this.payload = const Value.absent(),
    this.attempts = const Value.absent(),
    this.isEmergency = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
  });
  SyncQueueCompanion.insert({
    this.id = const Value.absent(),
    required String queueTable,
    required int recordLocalId,
    required String operation,
    required String payload,
    this.attempts = const Value.absent(),
    this.isEmergency = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
  })  : queueTable = Value(queueTable),
        recordLocalId = Value(recordLocalId),
        operation = Value(operation),
        payload = Value(payload);
  static Insertable<SyncQueueData> custom({
    Expression<int>? id,
    Expression<String>? queueTable,
    Expression<int>? recordLocalId,
    Expression<String>? operation,
    Expression<String>? payload,
    Expression<int>? attempts,
    Expression<bool>? isEmergency,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastAttemptAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (queueTable != null) 'queue_table': queueTable,
      if (recordLocalId != null) 'record_local_id': recordLocalId,
      if (operation != null) 'operation': operation,
      if (payload != null) 'payload': payload,
      if (attempts != null) 'attempts': attempts,
      if (isEmergency != null) 'is_emergency': isEmergency,
      if (createdAt != null) 'created_at': createdAt,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
    });
  }

  SyncQueueCompanion copyWith(
      {Value<int>? id,
      Value<String>? queueTable,
      Value<int>? recordLocalId,
      Value<String>? operation,
      Value<String>? payload,
      Value<int>? attempts,
      Value<bool>? isEmergency,
      Value<DateTime>? createdAt,
      Value<DateTime?>? lastAttemptAt}) {
    return SyncQueueCompanion(
      id: id ?? this.id,
      queueTable: queueTable ?? this.queueTable,
      recordLocalId: recordLocalId ?? this.recordLocalId,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      attempts: attempts ?? this.attempts,
      isEmergency: isEmergency ?? this.isEmergency,
      createdAt: createdAt ?? this.createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (queueTable.present) {
      map['queue_table'] = Variable<String>(queueTable.value);
    }
    if (recordLocalId.present) {
      map['record_local_id'] = Variable<int>(recordLocalId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (isEmergency.present) {
      map['is_emergency'] = Variable<bool>(isEmergency.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueCompanion(')
          ..write('id: $id, ')
          ..write('queueTable: $queueTable, ')
          ..write('recordLocalId: $recordLocalId, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('attempts: $attempts, ')
          ..write('isEmergency: $isEmergency, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptAt: $lastAttemptAt')
          ..write(')'))
        .toString();
  }
}

class $SyncQueueSnapshotTable extends SyncQueueSnapshot
    with TableInfo<$SyncQueueSnapshotTable, SyncQueueSnapshotData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncQueueSnapshotTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  @override
  List<GeneratedColumn> get $columns => [id];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_queue_snapshot';
  @override
  VerificationContext validateIntegrity(
      Insertable<SyncQueueSnapshotData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncQueueSnapshotData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncQueueSnapshotData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
    );
  }

  @override
  $SyncQueueSnapshotTable createAlias(String alias) {
    return $SyncQueueSnapshotTable(attachedDatabase, alias);
  }
}

class SyncQueueSnapshotData extends DataClass
    implements Insertable<SyncQueueSnapshotData> {
  final int id;
  const SyncQueueSnapshotData({required this.id});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    return map;
  }

  SyncQueueSnapshotCompanion toCompanion(bool nullToAbsent) {
    return SyncQueueSnapshotCompanion(
      id: Value(id),
    );
  }

  factory SyncQueueSnapshotData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncQueueSnapshotData(
      id: serializer.fromJson<int>(json['id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
    };
  }

  SyncQueueSnapshotData copyWith({int? id}) => SyncQueueSnapshotData(
        id: id ?? this.id,
      );
  SyncQueueSnapshotData copyWithCompanion(SyncQueueSnapshotCompanion data) {
    return SyncQueueSnapshotData(
      id: data.id.present ? data.id.value : this.id,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueSnapshotData(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => id.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncQueueSnapshotData && other.id == this.id);
}

class SyncQueueSnapshotCompanion
    extends UpdateCompanion<SyncQueueSnapshotData> {
  final Value<int> id;
  const SyncQueueSnapshotCompanion({
    this.id = const Value.absent(),
  });
  SyncQueueSnapshotCompanion.insert({
    this.id = const Value.absent(),
  });
  static Insertable<SyncQueueSnapshotData> custom({
    Expression<int>? id,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
    });
  }

  SyncQueueSnapshotCompanion copyWith({Value<int>? id}) {
    return SyncQueueSnapshotCompanion(
      id: id ?? this.id,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueSnapshotCompanion(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }
}

class $VersionHashesTable extends VersionHashes
    with TableInfo<$VersionHashesTable, VersionHashe> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VersionHashesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _tableMeta = const VerificationMeta('table');
  @override
  late final GeneratedColumn<String> table = GeneratedColumn<String>(
      'table_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recordLocalIdMeta =
      const VerificationMeta('recordLocalId');
  @override
  late final GeneratedColumn<int> recordLocalId = GeneratedColumn<int>(
      'record_local_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _hashMeta = const VerificationMeta('hash');
  @override
  late final GeneratedColumn<String> hash = GeneratedColumn<String>(
      'hash', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _snapshotJsonMeta =
      const VerificationMeta('snapshotJson');
  @override
  late final GeneratedColumn<String> snapshotJson = GeneratedColumn<String>(
      'snapshot_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _setAtMeta = const VerificationMeta('setAt');
  @override
  late final GeneratedColumn<DateTime> setAt = GeneratedColumn<DateTime>(
      'set_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, table, recordLocalId, hash, snapshotJson, setAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'version_hashes';
  @override
  VerificationContext validateIntegrity(Insertable<VersionHashe> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('table_name')) {
      context.handle(_tableMeta,
          table.isAcceptableOrUnknown(data['table_name']!, _tableMeta));
    } else if (isInserting) {
      context.missing(_tableMeta);
    }
    if (data.containsKey('record_local_id')) {
      context.handle(
          _recordLocalIdMeta,
          recordLocalId.isAcceptableOrUnknown(
              data['record_local_id']!, _recordLocalIdMeta));
    } else if (isInserting) {
      context.missing(_recordLocalIdMeta);
    }
    if (data.containsKey('hash')) {
      context.handle(
          _hashMeta, hash.isAcceptableOrUnknown(data['hash']!, _hashMeta));
    } else if (isInserting) {
      context.missing(_hashMeta);
    }
    if (data.containsKey('snapshot_json')) {
      context.handle(
          _snapshotJsonMeta,
          snapshotJson.isAcceptableOrUnknown(
              data['snapshot_json']!, _snapshotJsonMeta));
    }
    if (data.containsKey('set_at')) {
      context.handle(
          _setAtMeta, setAt.isAcceptableOrUnknown(data['set_at']!, _setAtMeta));
    } else if (isInserting) {
      context.missing(_setAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VersionHashe map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VersionHashe(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      table: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}table_name'])!,
      recordLocalId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}record_local_id'])!,
      hash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}hash'])!,
      snapshotJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}snapshot_json']),
      setAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}set_at'])!,
    );
  }

  @override
  $VersionHashesTable createAlias(String alias) {
    return $VersionHashesTable(attachedDatabase, alias);
  }
}

class VersionHashe extends DataClass implements Insertable<VersionHashe> {
  final int id;
  final String table;
  final int recordLocalId;
  final String hash;
  final String? snapshotJson;
  final DateTime setAt;
  const VersionHashe(
      {required this.id,
      required this.table,
      required this.recordLocalId,
      required this.hash,
      this.snapshotJson,
      required this.setAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['table_name'] = Variable<String>(table);
    map['record_local_id'] = Variable<int>(recordLocalId);
    map['hash'] = Variable<String>(hash);
    if (!nullToAbsent || snapshotJson != null) {
      map['snapshot_json'] = Variable<String>(snapshotJson);
    }
    map['set_at'] = Variable<DateTime>(setAt);
    return map;
  }

  VersionHashesCompanion toCompanion(bool nullToAbsent) {
    return VersionHashesCompanion(
      id: Value(id),
      table: Value(table),
      recordLocalId: Value(recordLocalId),
      hash: Value(hash),
      snapshotJson: snapshotJson == null && nullToAbsent
          ? const Value.absent()
          : Value(snapshotJson),
      setAt: Value(setAt),
    );
  }

  factory VersionHashe.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VersionHashe(
      id: serializer.fromJson<int>(json['id']),
      table: serializer.fromJson<String>(json['table']),
      recordLocalId: serializer.fromJson<int>(json['recordLocalId']),
      hash: serializer.fromJson<String>(json['hash']),
      snapshotJson: serializer.fromJson<String?>(json['snapshotJson']),
      setAt: serializer.fromJson<DateTime>(json['setAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'table': serializer.toJson<String>(table),
      'recordLocalId': serializer.toJson<int>(recordLocalId),
      'hash': serializer.toJson<String>(hash),
      'snapshotJson': serializer.toJson<String?>(snapshotJson),
      'setAt': serializer.toJson<DateTime>(setAt),
    };
  }

  VersionHashe copyWith(
          {int? id,
          String? table,
          int? recordLocalId,
          String? hash,
          Value<String?> snapshotJson = const Value.absent(),
          DateTime? setAt}) =>
      VersionHashe(
        id: id ?? this.id,
        table: table ?? this.table,
        recordLocalId: recordLocalId ?? this.recordLocalId,
        hash: hash ?? this.hash,
        snapshotJson:
            snapshotJson.present ? snapshotJson.value : this.snapshotJson,
        setAt: setAt ?? this.setAt,
      );
  VersionHashe copyWithCompanion(VersionHashesCompanion data) {
    return VersionHashe(
      id: data.id.present ? data.id.value : this.id,
      table: data.table.present ? data.table.value : this.table,
      recordLocalId: data.recordLocalId.present
          ? data.recordLocalId.value
          : this.recordLocalId,
      hash: data.hash.present ? data.hash.value : this.hash,
      snapshotJson: data.snapshotJson.present
          ? data.snapshotJson.value
          : this.snapshotJson,
      setAt: data.setAt.present ? data.setAt.value : this.setAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VersionHashe(')
          ..write('id: $id, ')
          ..write('table: $table, ')
          ..write('recordLocalId: $recordLocalId, ')
          ..write('hash: $hash, ')
          ..write('snapshotJson: $snapshotJson, ')
          ..write('setAt: $setAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, table, recordLocalId, hash, snapshotJson, setAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VersionHashe &&
          other.id == this.id &&
          other.table == this.table &&
          other.recordLocalId == this.recordLocalId &&
          other.hash == this.hash &&
          other.snapshotJson == this.snapshotJson &&
          other.setAt == this.setAt);
}

class VersionHashesCompanion extends UpdateCompanion<VersionHashe> {
  final Value<int> id;
  final Value<String> table;
  final Value<int> recordLocalId;
  final Value<String> hash;
  final Value<String?> snapshotJson;
  final Value<DateTime> setAt;
  const VersionHashesCompanion({
    this.id = const Value.absent(),
    this.table = const Value.absent(),
    this.recordLocalId = const Value.absent(),
    this.hash = const Value.absent(),
    this.snapshotJson = const Value.absent(),
    this.setAt = const Value.absent(),
  });
  VersionHashesCompanion.insert({
    this.id = const Value.absent(),
    required String table,
    required int recordLocalId,
    required String hash,
    this.snapshotJson = const Value.absent(),
    required DateTime setAt,
  })  : table = Value(table),
        recordLocalId = Value(recordLocalId),
        hash = Value(hash),
        setAt = Value(setAt);
  static Insertable<VersionHashe> custom({
    Expression<int>? id,
    Expression<String>? table,
    Expression<int>? recordLocalId,
    Expression<String>? hash,
    Expression<String>? snapshotJson,
    Expression<DateTime>? setAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (table != null) 'table_name': table,
      if (recordLocalId != null) 'record_local_id': recordLocalId,
      if (hash != null) 'hash': hash,
      if (snapshotJson != null) 'snapshot_json': snapshotJson,
      if (setAt != null) 'set_at': setAt,
    });
  }

  VersionHashesCompanion copyWith(
      {Value<int>? id,
      Value<String>? table,
      Value<int>? recordLocalId,
      Value<String>? hash,
      Value<String?>? snapshotJson,
      Value<DateTime>? setAt}) {
    return VersionHashesCompanion(
      id: id ?? this.id,
      table: table ?? this.table,
      recordLocalId: recordLocalId ?? this.recordLocalId,
      hash: hash ?? this.hash,
      snapshotJson: snapshotJson ?? this.snapshotJson,
      setAt: setAt ?? this.setAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (table.present) {
      map['table_name'] = Variable<String>(table.value);
    }
    if (recordLocalId.present) {
      map['record_local_id'] = Variable<int>(recordLocalId.value);
    }
    if (hash.present) {
      map['hash'] = Variable<String>(hash.value);
    }
    if (snapshotJson.present) {
      map['snapshot_json'] = Variable<String>(snapshotJson.value);
    }
    if (setAt.present) {
      map['set_at'] = Variable<DateTime>(setAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VersionHashesCompanion(')
          ..write('id: $id, ')
          ..write('table: $table, ')
          ..write('recordLocalId: $recordLocalId, ')
          ..write('hash: $hash, ')
          ..write('snapshotJson: $snapshotJson, ')
          ..write('setAt: $setAt')
          ..write(')'))
        .toString();
  }
}

class $ConflictsTable extends Conflicts
    with TableInfo<$ConflictsTable, Conflict> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConflictsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _recordTypeMeta =
      const VerificationMeta('recordType');
  @override
  late final GeneratedColumn<String> recordType = GeneratedColumn<String>(
      'record_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recordLocalIdMeta =
      const VerificationMeta('recordLocalId');
  @override
  late final GeneratedColumn<int> recordLocalId = GeneratedColumn<int>(
      'record_local_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _conflictingFieldsMeta =
      const VerificationMeta('conflictingFields');
  @override
  late final GeneratedColumn<String> conflictingFields =
      GeneratedColumn<String>('conflicting_fields', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _localValueMeta =
      const VerificationMeta('localValue');
  @override
  late final GeneratedColumn<String> localValue = GeneratedColumn<String>(
      'local_value', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _remoteValueMeta =
      const VerificationMeta('remoteValue');
  @override
  late final GeneratedColumn<String> remoteValue = GeneratedColumn<String>(
      'remote_value', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _resolutionMeta =
      const VerificationMeta('resolution');
  @override
  late final GeneratedColumn<String> resolution = GeneratedColumn<String>(
      'resolution', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('unresolved'));
  static const VerificationMeta _notifiedMeta =
      const VerificationMeta('notified');
  @override
  late final GeneratedColumn<bool> notified = GeneratedColumn<bool>(
      'notified', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("notified" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        recordType,
        recordLocalId,
        conflictingFields,
        localValue,
        remoteValue,
        resolution,
        notified,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conflicts';
  @override
  VerificationContext validateIntegrity(Insertable<Conflict> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('record_type')) {
      context.handle(
          _recordTypeMeta,
          recordType.isAcceptableOrUnknown(
              data['record_type']!, _recordTypeMeta));
    } else if (isInserting) {
      context.missing(_recordTypeMeta);
    }
    if (data.containsKey('record_local_id')) {
      context.handle(
          _recordLocalIdMeta,
          recordLocalId.isAcceptableOrUnknown(
              data['record_local_id']!, _recordLocalIdMeta));
    } else if (isInserting) {
      context.missing(_recordLocalIdMeta);
    }
    if (data.containsKey('conflicting_fields')) {
      context.handle(
          _conflictingFieldsMeta,
          conflictingFields.isAcceptableOrUnknown(
              data['conflicting_fields']!, _conflictingFieldsMeta));
    } else if (isInserting) {
      context.missing(_conflictingFieldsMeta);
    }
    if (data.containsKey('local_value')) {
      context.handle(
          _localValueMeta,
          localValue.isAcceptableOrUnknown(
              data['local_value']!, _localValueMeta));
    }
    if (data.containsKey('remote_value')) {
      context.handle(
          _remoteValueMeta,
          remoteValue.isAcceptableOrUnknown(
              data['remote_value']!, _remoteValueMeta));
    }
    if (data.containsKey('resolution')) {
      context.handle(
          _resolutionMeta,
          resolution.isAcceptableOrUnknown(
              data['resolution']!, _resolutionMeta));
    }
    if (data.containsKey('notified')) {
      context.handle(_notifiedMeta,
          notified.isAcceptableOrUnknown(data['notified']!, _notifiedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Conflict map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conflict(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      recordType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}record_type'])!,
      recordLocalId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}record_local_id'])!,
      conflictingFields: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}conflicting_fields'])!,
      localValue: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_value']),
      remoteValue: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}remote_value']),
      resolution: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}resolution'])!,
      notified: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}notified'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ConflictsTable createAlias(String alias) {
    return $ConflictsTable(attachedDatabase, alias);
  }
}

class Conflict extends DataClass implements Insertable<Conflict> {
  final int id;
  final String recordType;
  final int recordLocalId;
  final String conflictingFields;
  final String? localValue;
  final String? remoteValue;
  final String resolution;
  final bool notified;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Conflict(
      {required this.id,
      required this.recordType,
      required this.recordLocalId,
      required this.conflictingFields,
      this.localValue,
      this.remoteValue,
      required this.resolution,
      required this.notified,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['record_type'] = Variable<String>(recordType);
    map['record_local_id'] = Variable<int>(recordLocalId);
    map['conflicting_fields'] = Variable<String>(conflictingFields);
    if (!nullToAbsent || localValue != null) {
      map['local_value'] = Variable<String>(localValue);
    }
    if (!nullToAbsent || remoteValue != null) {
      map['remote_value'] = Variable<String>(remoteValue);
    }
    map['resolution'] = Variable<String>(resolution);
    map['notified'] = Variable<bool>(notified);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ConflictsCompanion toCompanion(bool nullToAbsent) {
    return ConflictsCompanion(
      id: Value(id),
      recordType: Value(recordType),
      recordLocalId: Value(recordLocalId),
      conflictingFields: Value(conflictingFields),
      localValue: localValue == null && nullToAbsent
          ? const Value.absent()
          : Value(localValue),
      remoteValue: remoteValue == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteValue),
      resolution: Value(resolution),
      notified: Value(notified),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Conflict.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conflict(
      id: serializer.fromJson<int>(json['id']),
      recordType: serializer.fromJson<String>(json['recordType']),
      recordLocalId: serializer.fromJson<int>(json['recordLocalId']),
      conflictingFields: serializer.fromJson<String>(json['conflictingFields']),
      localValue: serializer.fromJson<String?>(json['localValue']),
      remoteValue: serializer.fromJson<String?>(json['remoteValue']),
      resolution: serializer.fromJson<String>(json['resolution']),
      notified: serializer.fromJson<bool>(json['notified']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'recordType': serializer.toJson<String>(recordType),
      'recordLocalId': serializer.toJson<int>(recordLocalId),
      'conflictingFields': serializer.toJson<String>(conflictingFields),
      'localValue': serializer.toJson<String?>(localValue),
      'remoteValue': serializer.toJson<String?>(remoteValue),
      'resolution': serializer.toJson<String>(resolution),
      'notified': serializer.toJson<bool>(notified),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Conflict copyWith(
          {int? id,
          String? recordType,
          int? recordLocalId,
          String? conflictingFields,
          Value<String?> localValue = const Value.absent(),
          Value<String?> remoteValue = const Value.absent(),
          String? resolution,
          bool? notified,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Conflict(
        id: id ?? this.id,
        recordType: recordType ?? this.recordType,
        recordLocalId: recordLocalId ?? this.recordLocalId,
        conflictingFields: conflictingFields ?? this.conflictingFields,
        localValue: localValue.present ? localValue.value : this.localValue,
        remoteValue: remoteValue.present ? remoteValue.value : this.remoteValue,
        resolution: resolution ?? this.resolution,
        notified: notified ?? this.notified,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Conflict copyWithCompanion(ConflictsCompanion data) {
    return Conflict(
      id: data.id.present ? data.id.value : this.id,
      recordType:
          data.recordType.present ? data.recordType.value : this.recordType,
      recordLocalId: data.recordLocalId.present
          ? data.recordLocalId.value
          : this.recordLocalId,
      conflictingFields: data.conflictingFields.present
          ? data.conflictingFields.value
          : this.conflictingFields,
      localValue:
          data.localValue.present ? data.localValue.value : this.localValue,
      remoteValue:
          data.remoteValue.present ? data.remoteValue.value : this.remoteValue,
      resolution:
          data.resolution.present ? data.resolution.value : this.resolution,
      notified: data.notified.present ? data.notified.value : this.notified,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Conflict(')
          ..write('id: $id, ')
          ..write('recordType: $recordType, ')
          ..write('recordLocalId: $recordLocalId, ')
          ..write('conflictingFields: $conflictingFields, ')
          ..write('localValue: $localValue, ')
          ..write('remoteValue: $remoteValue, ')
          ..write('resolution: $resolution, ')
          ..write('notified: $notified, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      recordType,
      recordLocalId,
      conflictingFields,
      localValue,
      remoteValue,
      resolution,
      notified,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conflict &&
          other.id == this.id &&
          other.recordType == this.recordType &&
          other.recordLocalId == this.recordLocalId &&
          other.conflictingFields == this.conflictingFields &&
          other.localValue == this.localValue &&
          other.remoteValue == this.remoteValue &&
          other.resolution == this.resolution &&
          other.notified == this.notified &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ConflictsCompanion extends UpdateCompanion<Conflict> {
  final Value<int> id;
  final Value<String> recordType;
  final Value<int> recordLocalId;
  final Value<String> conflictingFields;
  final Value<String?> localValue;
  final Value<String?> remoteValue;
  final Value<String> resolution;
  final Value<bool> notified;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const ConflictsCompanion({
    this.id = const Value.absent(),
    this.recordType = const Value.absent(),
    this.recordLocalId = const Value.absent(),
    this.conflictingFields = const Value.absent(),
    this.localValue = const Value.absent(),
    this.remoteValue = const Value.absent(),
    this.resolution = const Value.absent(),
    this.notified = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ConflictsCompanion.insert({
    this.id = const Value.absent(),
    required String recordType,
    required int recordLocalId,
    required String conflictingFields,
    this.localValue = const Value.absent(),
    this.remoteValue = const Value.absent(),
    this.resolution = const Value.absent(),
    this.notified = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  })  : recordType = Value(recordType),
        recordLocalId = Value(recordLocalId),
        conflictingFields = Value(conflictingFields);
  static Insertable<Conflict> custom({
    Expression<int>? id,
    Expression<String>? recordType,
    Expression<int>? recordLocalId,
    Expression<String>? conflictingFields,
    Expression<String>? localValue,
    Expression<String>? remoteValue,
    Expression<String>? resolution,
    Expression<bool>? notified,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (recordType != null) 'record_type': recordType,
      if (recordLocalId != null) 'record_local_id': recordLocalId,
      if (conflictingFields != null) 'conflicting_fields': conflictingFields,
      if (localValue != null) 'local_value': localValue,
      if (remoteValue != null) 'remote_value': remoteValue,
      if (resolution != null) 'resolution': resolution,
      if (notified != null) 'notified': notified,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ConflictsCompanion copyWith(
      {Value<int>? id,
      Value<String>? recordType,
      Value<int>? recordLocalId,
      Value<String>? conflictingFields,
      Value<String?>? localValue,
      Value<String?>? remoteValue,
      Value<String>? resolution,
      Value<bool>? notified,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt}) {
    return ConflictsCompanion(
      id: id ?? this.id,
      recordType: recordType ?? this.recordType,
      recordLocalId: recordLocalId ?? this.recordLocalId,
      conflictingFields: conflictingFields ?? this.conflictingFields,
      localValue: localValue ?? this.localValue,
      remoteValue: remoteValue ?? this.remoteValue,
      resolution: resolution ?? this.resolution,
      notified: notified ?? this.notified,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (recordType.present) {
      map['record_type'] = Variable<String>(recordType.value);
    }
    if (recordLocalId.present) {
      map['record_local_id'] = Variable<int>(recordLocalId.value);
    }
    if (conflictingFields.present) {
      map['conflicting_fields'] = Variable<String>(conflictingFields.value);
    }
    if (localValue.present) {
      map['local_value'] = Variable<String>(localValue.value);
    }
    if (remoteValue.present) {
      map['remote_value'] = Variable<String>(remoteValue.value);
    }
    if (resolution.present) {
      map['resolution'] = Variable<String>(resolution.value);
    }
    if (notified.present) {
      map['notified'] = Variable<bool>(notified.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConflictsCompanion(')
          ..write('id: $id, ')
          ..write('recordType: $recordType, ')
          ..write('recordLocalId: $recordLocalId, ')
          ..write('conflictingFields: $conflictingFields, ')
          ..write('localValue: $localValue, ')
          ..write('remoteValue: $remoteValue, ')
          ..write('resolution: $resolution, ')
          ..write('notified: $notified, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $PaymentEventsTable extends PaymentEvents
    with TableInfo<$PaymentEventsTable, PaymentEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PaymentEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _transactionReferenceMeta =
      const VerificationMeta('transactionReference');
  @override
  late final GeneratedColumn<String> transactionReference =
      GeneratedColumn<String>('transaction_reference', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _confirmedByWebhookMeta =
      const VerificationMeta('confirmedByWebhook');
  @override
  late final GeneratedColumn<bool> confirmedByWebhook = GeneratedColumn<bool>(
      'confirmed_by_webhook', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("confirmed_by_webhook" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
      'amount', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _planMeta = const VerificationMeta('plan');
  @override
  late final GeneratedColumn<String> plan = GeneratedColumn<String>(
      'plan', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _confirmationDateMeta =
      const VerificationMeta('confirmationDate');
  @override
  late final GeneratedColumn<DateTime> confirmationDate =
      GeneratedColumn<DateTime>('confirmation_date', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        transactionReference,
        confirmedByWebhook,
        amount,
        plan,
        createdAt,
        confirmationDate
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'payment_events';
  @override
  VerificationContext validateIntegrity(Insertable<PaymentEvent> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('transaction_reference')) {
      context.handle(
          _transactionReferenceMeta,
          transactionReference.isAcceptableOrUnknown(
              data['transaction_reference']!, _transactionReferenceMeta));
    } else if (isInserting) {
      context.missing(_transactionReferenceMeta);
    }
    if (data.containsKey('confirmed_by_webhook')) {
      context.handle(
          _confirmedByWebhookMeta,
          confirmedByWebhook.isAcceptableOrUnknown(
              data['confirmed_by_webhook']!, _confirmedByWebhookMeta));
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('plan')) {
      context.handle(
          _planMeta, plan.isAcceptableOrUnknown(data['plan']!, _planMeta));
    } else if (isInserting) {
      context.missing(_planMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('confirmation_date')) {
      context.handle(
          _confirmationDateMeta,
          confirmationDate.isAcceptableOrUnknown(
              data['confirmation_date']!, _confirmationDateMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PaymentEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PaymentEvent(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      transactionReference: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}transaction_reference'])!,
      confirmedByWebhook: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}confirmed_by_webhook'])!,
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}amount'])!,
      plan: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}plan'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      confirmationDate: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}confirmation_date']),
    );
  }

  @override
  $PaymentEventsTable createAlias(String alias) {
    return $PaymentEventsTable(attachedDatabase, alias);
  }
}

class PaymentEvent extends DataClass implements Insertable<PaymentEvent> {
  final int id;
  final String transactionReference;
  final bool confirmedByWebhook;
  final int amount;
  final String plan;
  final DateTime createdAt;
  final DateTime? confirmationDate;
  const PaymentEvent(
      {required this.id,
      required this.transactionReference,
      required this.confirmedByWebhook,
      required this.amount,
      required this.plan,
      required this.createdAt,
      this.confirmationDate});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['transaction_reference'] = Variable<String>(transactionReference);
    map['confirmed_by_webhook'] = Variable<bool>(confirmedByWebhook);
    map['amount'] = Variable<int>(amount);
    map['plan'] = Variable<String>(plan);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || confirmationDate != null) {
      map['confirmation_date'] = Variable<DateTime>(confirmationDate);
    }
    return map;
  }

  PaymentEventsCompanion toCompanion(bool nullToAbsent) {
    return PaymentEventsCompanion(
      id: Value(id),
      transactionReference: Value(transactionReference),
      confirmedByWebhook: Value(confirmedByWebhook),
      amount: Value(amount),
      plan: Value(plan),
      createdAt: Value(createdAt),
      confirmationDate: confirmationDate == null && nullToAbsent
          ? const Value.absent()
          : Value(confirmationDate),
    );
  }

  factory PaymentEvent.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PaymentEvent(
      id: serializer.fromJson<int>(json['id']),
      transactionReference:
          serializer.fromJson<String>(json['transactionReference']),
      confirmedByWebhook: serializer.fromJson<bool>(json['confirmedByWebhook']),
      amount: serializer.fromJson<int>(json['amount']),
      plan: serializer.fromJson<String>(json['plan']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      confirmationDate:
          serializer.fromJson<DateTime?>(json['confirmationDate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'transactionReference': serializer.toJson<String>(transactionReference),
      'confirmedByWebhook': serializer.toJson<bool>(confirmedByWebhook),
      'amount': serializer.toJson<int>(amount),
      'plan': serializer.toJson<String>(plan),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'confirmationDate': serializer.toJson<DateTime?>(confirmationDate),
    };
  }

  PaymentEvent copyWith(
          {int? id,
          String? transactionReference,
          bool? confirmedByWebhook,
          int? amount,
          String? plan,
          DateTime? createdAt,
          Value<DateTime?> confirmationDate = const Value.absent()}) =>
      PaymentEvent(
        id: id ?? this.id,
        transactionReference: transactionReference ?? this.transactionReference,
        confirmedByWebhook: confirmedByWebhook ?? this.confirmedByWebhook,
        amount: amount ?? this.amount,
        plan: plan ?? this.plan,
        createdAt: createdAt ?? this.createdAt,
        confirmationDate: confirmationDate.present
            ? confirmationDate.value
            : this.confirmationDate,
      );
  PaymentEvent copyWithCompanion(PaymentEventsCompanion data) {
    return PaymentEvent(
      id: data.id.present ? data.id.value : this.id,
      transactionReference: data.transactionReference.present
          ? data.transactionReference.value
          : this.transactionReference,
      confirmedByWebhook: data.confirmedByWebhook.present
          ? data.confirmedByWebhook.value
          : this.confirmedByWebhook,
      amount: data.amount.present ? data.amount.value : this.amount,
      plan: data.plan.present ? data.plan.value : this.plan,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      confirmationDate: data.confirmationDate.present
          ? data.confirmationDate.value
          : this.confirmationDate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PaymentEvent(')
          ..write('id: $id, ')
          ..write('transactionReference: $transactionReference, ')
          ..write('confirmedByWebhook: $confirmedByWebhook, ')
          ..write('amount: $amount, ')
          ..write('plan: $plan, ')
          ..write('createdAt: $createdAt, ')
          ..write('confirmationDate: $confirmationDate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, transactionReference, confirmedByWebhook,
      amount, plan, createdAt, confirmationDate);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PaymentEvent &&
          other.id == this.id &&
          other.transactionReference == this.transactionReference &&
          other.confirmedByWebhook == this.confirmedByWebhook &&
          other.amount == this.amount &&
          other.plan == this.plan &&
          other.createdAt == this.createdAt &&
          other.confirmationDate == this.confirmationDate);
}

class PaymentEventsCompanion extends UpdateCompanion<PaymentEvent> {
  final Value<int> id;
  final Value<String> transactionReference;
  final Value<bool> confirmedByWebhook;
  final Value<int> amount;
  final Value<String> plan;
  final Value<DateTime> createdAt;
  final Value<DateTime?> confirmationDate;
  const PaymentEventsCompanion({
    this.id = const Value.absent(),
    this.transactionReference = const Value.absent(),
    this.confirmedByWebhook = const Value.absent(),
    this.amount = const Value.absent(),
    this.plan = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.confirmationDate = const Value.absent(),
  });
  PaymentEventsCompanion.insert({
    this.id = const Value.absent(),
    required String transactionReference,
    this.confirmedByWebhook = const Value.absent(),
    required int amount,
    required String plan,
    this.createdAt = const Value.absent(),
    this.confirmationDate = const Value.absent(),
  })  : transactionReference = Value(transactionReference),
        amount = Value(amount),
        plan = Value(plan);
  static Insertable<PaymentEvent> custom({
    Expression<int>? id,
    Expression<String>? transactionReference,
    Expression<bool>? confirmedByWebhook,
    Expression<int>? amount,
    Expression<String>? plan,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? confirmationDate,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (transactionReference != null)
        'transaction_reference': transactionReference,
      if (confirmedByWebhook != null)
        'confirmed_by_webhook': confirmedByWebhook,
      if (amount != null) 'amount': amount,
      if (plan != null) 'plan': plan,
      if (createdAt != null) 'created_at': createdAt,
      if (confirmationDate != null) 'confirmation_date': confirmationDate,
    });
  }

  PaymentEventsCompanion copyWith(
      {Value<int>? id,
      Value<String>? transactionReference,
      Value<bool>? confirmedByWebhook,
      Value<int>? amount,
      Value<String>? plan,
      Value<DateTime>? createdAt,
      Value<DateTime?>? confirmationDate}) {
    return PaymentEventsCompanion(
      id: id ?? this.id,
      transactionReference: transactionReference ?? this.transactionReference,
      confirmedByWebhook: confirmedByWebhook ?? this.confirmedByWebhook,
      amount: amount ?? this.amount,
      plan: plan ?? this.plan,
      createdAt: createdAt ?? this.createdAt,
      confirmationDate: confirmationDate ?? this.confirmationDate,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (transactionReference.present) {
      map['transaction_reference'] =
          Variable<String>(transactionReference.value);
    }
    if (confirmedByWebhook.present) {
      map['confirmed_by_webhook'] = Variable<bool>(confirmedByWebhook.value);
    }
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (plan.present) {
      map['plan'] = Variable<String>(plan.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (confirmationDate.present) {
      map['confirmation_date'] = Variable<DateTime>(confirmationDate.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PaymentEventsCompanion(')
          ..write('id: $id, ')
          ..write('transactionReference: $transactionReference, ')
          ..write('confirmedByWebhook: $confirmedByWebhook, ')
          ..write('amount: $amount, ')
          ..write('plan: $plan, ')
          ..write('createdAt: $createdAt, ')
          ..write('confirmationDate: $confirmationDate')
          ..write(')'))
        .toString();
  }
}

class $RecoveryCodesTable extends RecoveryCodes
    with TableInfo<$RecoveryCodesTable, RecoveryCode> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecoveryCodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  @override
  List<GeneratedColumn> get $columns => [id];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recovery_codes';
  @override
  VerificationContext validateIntegrity(Insertable<RecoveryCode> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecoveryCode map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecoveryCode(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
    );
  }

  @override
  $RecoveryCodesTable createAlias(String alias) {
    return $RecoveryCodesTable(attachedDatabase, alias);
  }
}

class RecoveryCode extends DataClass implements Insertable<RecoveryCode> {
  final int id;
  const RecoveryCode({required this.id});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    return map;
  }

  RecoveryCodesCompanion toCompanion(bool nullToAbsent) {
    return RecoveryCodesCompanion(
      id: Value(id),
    );
  }

  factory RecoveryCode.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecoveryCode(
      id: serializer.fromJson<int>(json['id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
    };
  }

  RecoveryCode copyWith({int? id}) => RecoveryCode(
        id: id ?? this.id,
      );
  RecoveryCode copyWithCompanion(RecoveryCodesCompanion data) {
    return RecoveryCode(
      id: data.id.present ? data.id.value : this.id,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecoveryCode(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => id.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is RecoveryCode && other.id == this.id);
}

class RecoveryCodesCompanion extends UpdateCompanion<RecoveryCode> {
  final Value<int> id;
  const RecoveryCodesCompanion({
    this.id = const Value.absent(),
  });
  RecoveryCodesCompanion.insert({
    this.id = const Value.absent(),
  });
  static Insertable<RecoveryCode> custom({
    Expression<int>? id,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
    });
  }

  RecoveryCodesCompanion copyWith({Value<int>? id}) {
    return RecoveryCodesCompanion(
      id: id ?? this.id,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecoveryCodesCompanion(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }
}

class $PendingRecoveryRequestsTable extends PendingRecoveryRequests
    with TableInfo<$PendingRecoveryRequestsTable, PendingRecoveryRequest> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingRecoveryRequestsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
      'email', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _attemptedAtMeta =
      const VerificationMeta('attemptedAt');
  @override
  late final GeneratedColumn<DateTime> attemptedAt = GeneratedColumn<DateTime>(
      'attempted_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, email, attemptedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_recovery_requests';
  @override
  VerificationContext validateIntegrity(
      Insertable<PendingRecoveryRequest> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('email')) {
      context.handle(
          _emailMeta, email.isAcceptableOrUnknown(data['email']!, _emailMeta));
    } else if (isInserting) {
      context.missing(_emailMeta);
    }
    if (data.containsKey('attempted_at')) {
      context.handle(
          _attemptedAtMeta,
          attemptedAt.isAcceptableOrUnknown(
              data['attempted_at']!, _attemptedAtMeta));
    } else if (isInserting) {
      context.missing(_attemptedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingRecoveryRequest map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingRecoveryRequest(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      email: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}email'])!,
      attemptedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}attempted_at'])!,
    );
  }

  @override
  $PendingRecoveryRequestsTable createAlias(String alias) {
    return $PendingRecoveryRequestsTable(attachedDatabase, alias);
  }
}

class PendingRecoveryRequest extends DataClass
    implements Insertable<PendingRecoveryRequest> {
  final int id;
  final String email;
  final DateTime attemptedAt;
  const PendingRecoveryRequest(
      {required this.id, required this.email, required this.attemptedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['email'] = Variable<String>(email);
    map['attempted_at'] = Variable<DateTime>(attemptedAt);
    return map;
  }

  PendingRecoveryRequestsCompanion toCompanion(bool nullToAbsent) {
    return PendingRecoveryRequestsCompanion(
      id: Value(id),
      email: Value(email),
      attemptedAt: Value(attemptedAt),
    );
  }

  factory PendingRecoveryRequest.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingRecoveryRequest(
      id: serializer.fromJson<int>(json['id']),
      email: serializer.fromJson<String>(json['email']),
      attemptedAt: serializer.fromJson<DateTime>(json['attemptedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'email': serializer.toJson<String>(email),
      'attemptedAt': serializer.toJson<DateTime>(attemptedAt),
    };
  }

  PendingRecoveryRequest copyWith(
          {int? id, String? email, DateTime? attemptedAt}) =>
      PendingRecoveryRequest(
        id: id ?? this.id,
        email: email ?? this.email,
        attemptedAt: attemptedAt ?? this.attemptedAt,
      );
  PendingRecoveryRequest copyWithCompanion(
      PendingRecoveryRequestsCompanion data) {
    return PendingRecoveryRequest(
      id: data.id.present ? data.id.value : this.id,
      email: data.email.present ? data.email.value : this.email,
      attemptedAt:
          data.attemptedAt.present ? data.attemptedAt.value : this.attemptedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingRecoveryRequest(')
          ..write('id: $id, ')
          ..write('email: $email, ')
          ..write('attemptedAt: $attemptedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, email, attemptedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingRecoveryRequest &&
          other.id == this.id &&
          other.email == this.email &&
          other.attemptedAt == this.attemptedAt);
}

class PendingRecoveryRequestsCompanion
    extends UpdateCompanion<PendingRecoveryRequest> {
  final Value<int> id;
  final Value<String> email;
  final Value<DateTime> attemptedAt;
  const PendingRecoveryRequestsCompanion({
    this.id = const Value.absent(),
    this.email = const Value.absent(),
    this.attemptedAt = const Value.absent(),
  });
  PendingRecoveryRequestsCompanion.insert({
    this.id = const Value.absent(),
    required String email,
    required DateTime attemptedAt,
  })  : email = Value(email),
        attemptedAt = Value(attemptedAt);
  static Insertable<PendingRecoveryRequest> custom({
    Expression<int>? id,
    Expression<String>? email,
    Expression<DateTime>? attemptedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (email != null) 'email': email,
      if (attemptedAt != null) 'attempted_at': attemptedAt,
    });
  }

  PendingRecoveryRequestsCompanion copyWith(
      {Value<int>? id, Value<String>? email, Value<DateTime>? attemptedAt}) {
    return PendingRecoveryRequestsCompanion(
      id: id ?? this.id,
      email: email ?? this.email,
      attemptedAt: attemptedAt ?? this.attemptedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (attemptedAt.present) {
      map['attempted_at'] = Variable<DateTime>(attemptedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingRecoveryRequestsCompanion(')
          ..write('id: $id, ')
          ..write('email: $email, ')
          ..write('attemptedAt: $attemptedAt')
          ..write(')'))
        .toString();
  }
}

class $TeacherDevicesTable extends TeacherDevices
    with TableInfo<$TeacherDevicesTable, TeacherDevice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TeacherDevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  @override
  List<GeneratedColumn> get $columns => [id];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'teacher_devices';
  @override
  VerificationContext validateIntegrity(Insertable<TeacherDevice> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TeacherDevice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TeacherDevice(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
    );
  }

  @override
  $TeacherDevicesTable createAlias(String alias) {
    return $TeacherDevicesTable(attachedDatabase, alias);
  }
}

class TeacherDevice extends DataClass implements Insertable<TeacherDevice> {
  final int id;
  const TeacherDevice({required this.id});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    return map;
  }

  TeacherDevicesCompanion toCompanion(bool nullToAbsent) {
    return TeacherDevicesCompanion(
      id: Value(id),
    );
  }

  factory TeacherDevice.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TeacherDevice(
      id: serializer.fromJson<int>(json['id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
    };
  }

  TeacherDevice copyWith({int? id}) => TeacherDevice(
        id: id ?? this.id,
      );
  TeacherDevice copyWithCompanion(TeacherDevicesCompanion data) {
    return TeacherDevice(
      id: data.id.present ? data.id.value : this.id,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TeacherDevice(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => id.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TeacherDevice && other.id == this.id);
}

class TeacherDevicesCompanion extends UpdateCompanion<TeacherDevice> {
  final Value<int> id;
  const TeacherDevicesCompanion({
    this.id = const Value.absent(),
  });
  TeacherDevicesCompanion.insert({
    this.id = const Value.absent(),
  });
  static Insertable<TeacherDevice> custom({
    Expression<int>? id,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
    });
  }

  TeacherDevicesCompanion copyWith({Value<int>? id}) {
    return TeacherDevicesCompanion(
      id: id ?? this.id,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TeacherDevicesCompanion(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }
}

class $SchemeGenerationQueueTable extends SchemeGenerationQueue
    with TableInfo<$SchemeGenerationQueueTable, SchemeGenerationQueueData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SchemeGenerationQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  @override
  List<GeneratedColumn> get $columns => [id];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scheme_generation_queue';
  @override
  VerificationContext validateIntegrity(
      Insertable<SchemeGenerationQueueData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SchemeGenerationQueueData map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SchemeGenerationQueueData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
    );
  }

  @override
  $SchemeGenerationQueueTable createAlias(String alias) {
    return $SchemeGenerationQueueTable(attachedDatabase, alias);
  }
}

class SchemeGenerationQueueData extends DataClass
    implements Insertable<SchemeGenerationQueueData> {
  final int id;
  const SchemeGenerationQueueData({required this.id});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    return map;
  }

  SchemeGenerationQueueCompanion toCompanion(bool nullToAbsent) {
    return SchemeGenerationQueueCompanion(
      id: Value(id),
    );
  }

  factory SchemeGenerationQueueData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SchemeGenerationQueueData(
      id: serializer.fromJson<int>(json['id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
    };
  }

  SchemeGenerationQueueData copyWith({int? id}) => SchemeGenerationQueueData(
        id: id ?? this.id,
      );
  SchemeGenerationQueueData copyWithCompanion(
      SchemeGenerationQueueCompanion data) {
    return SchemeGenerationQueueData(
      id: data.id.present ? data.id.value : this.id,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SchemeGenerationQueueData(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => id.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SchemeGenerationQueueData && other.id == this.id);
}

class SchemeGenerationQueueCompanion
    extends UpdateCompanion<SchemeGenerationQueueData> {
  final Value<int> id;
  const SchemeGenerationQueueCompanion({
    this.id = const Value.absent(),
  });
  SchemeGenerationQueueCompanion.insert({
    this.id = const Value.absent(),
  });
  static Insertable<SchemeGenerationQueueData> custom({
    Expression<int>? id,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
    });
  }

  SchemeGenerationQueueCompanion copyWith({Value<int>? id}) {
    return SchemeGenerationQueueCompanion(
      id: id ?? this.id,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SchemeGenerationQueueCompanion(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }
}

class $PdfCacheTable extends PdfCache
    with TableInfo<$PdfCacheTable, PdfCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PdfCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cacheKeyMeta =
      const VerificationMeta('cacheKey');
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
      'cache_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _pdfDataMeta =
      const VerificationMeta('pdfData');
  @override
  late final GeneratedColumn<Uint8List> pdfData = GeneratedColumn<Uint8List>(
      'pdf_data', aliasedName, false,
      type: DriftSqlType.blob, requiredDuringInsert: true);
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [cacheKey, pdfData, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pdf_cache';
  @override
  VerificationContext validateIntegrity(Insertable<PdfCacheData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cache_key')) {
      context.handle(_cacheKeyMeta,
          cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta));
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('pdf_data')) {
      context.handle(_pdfDataMeta,
          pdfData.isAcceptableOrUnknown(data['pdf_data']!, _pdfDataMeta));
    } else if (isInserting) {
      context.missing(_pdfDataMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cacheKey};
  @override
  PdfCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PdfCacheData(
      cacheKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cache_key'])!,
      pdfData: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}pdf_data'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $PdfCacheTable createAlias(String alias) {
    return $PdfCacheTable(attachedDatabase, alias);
  }
}

class PdfCacheData extends DataClass implements Insertable<PdfCacheData> {
  final String cacheKey;
  final Uint8List pdfData;
  final DateTime cachedAt;
  const PdfCacheData(
      {required this.cacheKey, required this.pdfData, required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cache_key'] = Variable<String>(cacheKey);
    map['pdf_data'] = Variable<Uint8List>(pdfData);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  PdfCacheCompanion toCompanion(bool nullToAbsent) {
    return PdfCacheCompanion(
      cacheKey: Value(cacheKey),
      pdfData: Value(pdfData),
      cachedAt: Value(cachedAt),
    );
  }

  factory PdfCacheData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PdfCacheData(
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      pdfData: serializer.fromJson<Uint8List>(json['pdfData']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cacheKey': serializer.toJson<String>(cacheKey),
      'pdfData': serializer.toJson<Uint8List>(pdfData),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  PdfCacheData copyWith(
          {String? cacheKey, Uint8List? pdfData, DateTime? cachedAt}) =>
      PdfCacheData(
        cacheKey: cacheKey ?? this.cacheKey,
        pdfData: pdfData ?? this.pdfData,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  PdfCacheData copyWithCompanion(PdfCacheCompanion data) {
    return PdfCacheData(
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      pdfData: data.pdfData.present ? data.pdfData.value : this.pdfData,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PdfCacheData(')
          ..write('cacheKey: $cacheKey, ')
          ..write('pdfData: $pdfData, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(cacheKey, $driftBlobEquality.hash(pdfData), cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PdfCacheData &&
          other.cacheKey == this.cacheKey &&
          $driftBlobEquality.equals(other.pdfData, this.pdfData) &&
          other.cachedAt == this.cachedAt);
}

class PdfCacheCompanion extends UpdateCompanion<PdfCacheData> {
  final Value<String> cacheKey;
  final Value<Uint8List> pdfData;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const PdfCacheCompanion({
    this.cacheKey = const Value.absent(),
    this.pdfData = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PdfCacheCompanion.insert({
    required String cacheKey,
    required Uint8List pdfData,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  })  : cacheKey = Value(cacheKey),
        pdfData = Value(pdfData),
        cachedAt = Value(cachedAt);
  static Insertable<PdfCacheData> custom({
    Expression<String>? cacheKey,
    Expression<Uint8List>? pdfData,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cacheKey != null) 'cache_key': cacheKey,
      if (pdfData != null) 'pdf_data': pdfData,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PdfCacheCompanion copyWith(
      {Value<String>? cacheKey,
      Value<Uint8List>? pdfData,
      Value<DateTime>? cachedAt,
      Value<int>? rowid}) {
    return PdfCacheCompanion(
      cacheKey: cacheKey ?? this.cacheKey,
      pdfData: pdfData ?? this.pdfData,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (pdfData.present) {
      map['pdf_data'] = Variable<Uint8List>(pdfData.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PdfCacheCompanion(')
          ..write('cacheKey: $cacheKey, ')
          ..write('pdfData: $pdfData, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TeacherSubjectsTable extends TeacherSubjects
    with TableInfo<$TeacherSubjectsTable, TeacherSubject> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TeacherSubjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _teacherLocalIdMeta =
      const VerificationMeta('teacherLocalId');
  @override
  late final GeneratedColumn<int> teacherLocalId = GeneratedColumn<int>(
      'teacher_local_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES teachers (local_id)'));
  static const VerificationMeta _subjectIdMeta =
      const VerificationMeta('subjectId');
  @override
  late final GeneratedColumn<int> subjectId = GeneratedColumn<int>(
      'subject_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES subjects (id)'));
  @override
  List<GeneratedColumn> get $columns => [id, teacherLocalId, subjectId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'teacher_subjects';
  @override
  VerificationContext validateIntegrity(Insertable<TeacherSubject> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('teacher_local_id')) {
      context.handle(
          _teacherLocalIdMeta,
          teacherLocalId.isAcceptableOrUnknown(
              data['teacher_local_id']!, _teacherLocalIdMeta));
    } else if (isInserting) {
      context.missing(_teacherLocalIdMeta);
    }
    if (data.containsKey('subject_id')) {
      context.handle(_subjectIdMeta,
          subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta));
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TeacherSubject map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TeacherSubject(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      teacherLocalId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}teacher_local_id'])!,
      subjectId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}subject_id'])!,
    );
  }

  @override
  $TeacherSubjectsTable createAlias(String alias) {
    return $TeacherSubjectsTable(attachedDatabase, alias);
  }
}

class TeacherSubject extends DataClass implements Insertable<TeacherSubject> {
  final int id;
  final int teacherLocalId;
  final int subjectId;
  const TeacherSubject(
      {required this.id,
      required this.teacherLocalId,
      required this.subjectId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['teacher_local_id'] = Variable<int>(teacherLocalId);
    map['subject_id'] = Variable<int>(subjectId);
    return map;
  }

  TeacherSubjectsCompanion toCompanion(bool nullToAbsent) {
    return TeacherSubjectsCompanion(
      id: Value(id),
      teacherLocalId: Value(teacherLocalId),
      subjectId: Value(subjectId),
    );
  }

  factory TeacherSubject.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TeacherSubject(
      id: serializer.fromJson<int>(json['id']),
      teacherLocalId: serializer.fromJson<int>(json['teacherLocalId']),
      subjectId: serializer.fromJson<int>(json['subjectId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'teacherLocalId': serializer.toJson<int>(teacherLocalId),
      'subjectId': serializer.toJson<int>(subjectId),
    };
  }

  TeacherSubject copyWith({int? id, int? teacherLocalId, int? subjectId}) =>
      TeacherSubject(
        id: id ?? this.id,
        teacherLocalId: teacherLocalId ?? this.teacherLocalId,
        subjectId: subjectId ?? this.subjectId,
      );
  TeacherSubject copyWithCompanion(TeacherSubjectsCompanion data) {
    return TeacherSubject(
      id: data.id.present ? data.id.value : this.id,
      teacherLocalId: data.teacherLocalId.present
          ? data.teacherLocalId.value
          : this.teacherLocalId,
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TeacherSubject(')
          ..write('id: $id, ')
          ..write('teacherLocalId: $teacherLocalId, ')
          ..write('subjectId: $subjectId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, teacherLocalId, subjectId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TeacherSubject &&
          other.id == this.id &&
          other.teacherLocalId == this.teacherLocalId &&
          other.subjectId == this.subjectId);
}

class TeacherSubjectsCompanion extends UpdateCompanion<TeacherSubject> {
  final Value<int> id;
  final Value<int> teacherLocalId;
  final Value<int> subjectId;
  const TeacherSubjectsCompanion({
    this.id = const Value.absent(),
    this.teacherLocalId = const Value.absent(),
    this.subjectId = const Value.absent(),
  });
  TeacherSubjectsCompanion.insert({
    this.id = const Value.absent(),
    required int teacherLocalId,
    required int subjectId,
  })  : teacherLocalId = Value(teacherLocalId),
        subjectId = Value(subjectId);
  static Insertable<TeacherSubject> custom({
    Expression<int>? id,
    Expression<int>? teacherLocalId,
    Expression<int>? subjectId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (teacherLocalId != null) 'teacher_local_id': teacherLocalId,
      if (subjectId != null) 'subject_id': subjectId,
    });
  }

  TeacherSubjectsCompanion copyWith(
      {Value<int>? id, Value<int>? teacherLocalId, Value<int>? subjectId}) {
    return TeacherSubjectsCompanion(
      id: id ?? this.id,
      teacherLocalId: teacherLocalId ?? this.teacherLocalId,
      subjectId: subjectId ?? this.subjectId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (teacherLocalId.present) {
      map['teacher_local_id'] = Variable<int>(teacherLocalId.value);
    }
    if (subjectId.present) {
      map['subject_id'] = Variable<int>(subjectId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TeacherSubjectsCompanion(')
          ..write('id: $id, ')
          ..write('teacherLocalId: $teacherLocalId, ')
          ..write('subjectId: $subjectId')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SchoolsTable schools = $SchoolsTable(this);
  late final $TeachersTable teachers = $TeachersTable(this);
  late final $SubjectsTable subjects = $SubjectsTable(this);
  late final $LessonsTable lessons = $LessonsTable(this);
  late final $SchemeOfWorkTable schemeOfWork = $SchemeOfWorkTable(this);
  late final $ExamsTable exams = $ExamsTable(this);
  late final $ProgressLogsTable progressLogs = $ProgressLogsTable(this);
  late final $VaultItemsTable vaultItems = $VaultItemsTable(this);
  late final $SecurityConfigTable securityConfig = $SecurityConfigTable(this);
  late final $SyncQueueTable syncQueue = $SyncQueueTable(this);
  late final $SyncQueueSnapshotTable syncQueueSnapshot =
      $SyncQueueSnapshotTable(this);
  late final $VersionHashesTable versionHashes = $VersionHashesTable(this);
  late final $ConflictsTable conflicts = $ConflictsTable(this);
  late final $PaymentEventsTable paymentEvents = $PaymentEventsTable(this);
  late final $RecoveryCodesTable recoveryCodes = $RecoveryCodesTable(this);
  late final $PendingRecoveryRequestsTable pendingRecoveryRequests =
      $PendingRecoveryRequestsTable(this);
  late final $TeacherDevicesTable teacherDevices = $TeacherDevicesTable(this);
  late final $SchemeGenerationQueueTable schemeGenerationQueue =
      $SchemeGenerationQueueTable(this);
  late final $PdfCacheTable pdfCache = $PdfCacheTable(this);
  late final $TeacherSubjectsTable teacherSubjects =
      $TeacherSubjectsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        schools,
        teachers,
        subjects,
        lessons,
        schemeOfWork,
        exams,
        progressLogs,
        vaultItems,
        securityConfig,
        syncQueue,
        syncQueueSnapshot,
        versionHashes,
        conflicts,
        paymentEvents,
        recoveryCodes,
        pendingRecoveryRequests,
        teacherDevices,
        schemeGenerationQueue,
        pdfCache,
        teacherSubjects
      ];
}

typedef $$SchoolsTableCreateCompanionBuilder = SchoolsCompanion Function({
  Value<int> localId,
  Value<String?> serverId,
  required String schoolName,
  required String shortCode,
  Value<String?> logoUrl,
  Value<String> subscriptionTier,
  Value<String> activeCurriculum,
  Value<String?> activeCurriculumVersion,
  Value<int> totalSeats,
  Value<String?> schoolMasterKeyWrapped,
  Value<String?> adminRecoveryEmail,
  Value<bool> adminRecoveryEmailVerified,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> updateCounter,
  Value<bool> isDeleted,
  Value<String?> lastModifiedBy,
});
typedef $$SchoolsTableUpdateCompanionBuilder = SchoolsCompanion Function({
  Value<int> localId,
  Value<String?> serverId,
  Value<String> schoolName,
  Value<String> shortCode,
  Value<String?> logoUrl,
  Value<String> subscriptionTier,
  Value<String> activeCurriculum,
  Value<String?> activeCurriculumVersion,
  Value<int> totalSeats,
  Value<String?> schoolMasterKeyWrapped,
  Value<String?> adminRecoveryEmail,
  Value<bool> adminRecoveryEmailVerified,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> updateCounter,
  Value<bool> isDeleted,
  Value<String?> lastModifiedBy,
});

final class $$SchoolsTableReferences
    extends BaseReferences<_$AppDatabase, $SchoolsTable, School> {
  $$SchoolsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TeachersTable, List<Teacher>> _teachersRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.teachers,
          aliasName: $_aliasNameGenerator(
              db.schools.localId, db.teachers.schoolLocalId));

  $$TeachersTableProcessedTableManager get teachersRefs {
    final manager = $$TeachersTableTableManager($_db, $_db.teachers).filter(
        (f) =>
            f.schoolLocalId.localId.sqlEquals($_itemColumn<int>('local_id')!));

    final cache = $_typedResult.readTableOrNull(_teachersRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$SchoolsTableFilterComposer
    extends Composer<_$AppDatabase, $SchoolsTable> {
  $$SchoolsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get localId => $composableBuilder(
      column: $table.localId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get schoolName => $composableBuilder(
      column: $table.schoolName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get shortCode => $composableBuilder(
      column: $table.shortCode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get logoUrl => $composableBuilder(
      column: $table.logoUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get subscriptionTier => $composableBuilder(
      column: $table.subscriptionTier,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get activeCurriculum => $composableBuilder(
      column: $table.activeCurriculum,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get activeCurriculumVersion => $composableBuilder(
      column: $table.activeCurriculumVersion,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get totalSeats => $composableBuilder(
      column: $table.totalSeats, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get schoolMasterKeyWrapped => $composableBuilder(
      column: $table.schoolMasterKeyWrapped,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get adminRecoveryEmail => $composableBuilder(
      column: $table.adminRecoveryEmail,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get adminRecoveryEmailVerified => $composableBuilder(
      column: $table.adminRecoveryEmailVerified,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updateCounter => $composableBuilder(
      column: $table.updateCounter, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isDeleted => $composableBuilder(
      column: $table.isDeleted, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastModifiedBy => $composableBuilder(
      column: $table.lastModifiedBy,
      builder: (column) => ColumnFilters(column));

  Expression<bool> teachersRefs(
      Expression<bool> Function($$TeachersTableFilterComposer f) f) {
    final $$TeachersTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.localId,
        referencedTable: $db.teachers,
        getReferencedColumn: (t) => t.schoolLocalId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TeachersTableFilterComposer(
              $db: $db,
              $table: $db.teachers,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SchoolsTableOrderingComposer
    extends Composer<_$AppDatabase, $SchoolsTable> {
  $$SchoolsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get localId => $composableBuilder(
      column: $table.localId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get schoolName => $composableBuilder(
      column: $table.schoolName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get shortCode => $composableBuilder(
      column: $table.shortCode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get logoUrl => $composableBuilder(
      column: $table.logoUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get subscriptionTier => $composableBuilder(
      column: $table.subscriptionTier,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get activeCurriculum => $composableBuilder(
      column: $table.activeCurriculum,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get activeCurriculumVersion => $composableBuilder(
      column: $table.activeCurriculumVersion,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get totalSeats => $composableBuilder(
      column: $table.totalSeats, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get schoolMasterKeyWrapped => $composableBuilder(
      column: $table.schoolMasterKeyWrapped,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get adminRecoveryEmail => $composableBuilder(
      column: $table.adminRecoveryEmail,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get adminRecoveryEmailVerified => $composableBuilder(
      column: $table.adminRecoveryEmailVerified,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updateCounter => $composableBuilder(
      column: $table.updateCounter,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
      column: $table.isDeleted, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastModifiedBy => $composableBuilder(
      column: $table.lastModifiedBy,
      builder: (column) => ColumnOrderings(column));
}

class $$SchoolsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SchoolsTable> {
  $$SchoolsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get schoolName => $composableBuilder(
      column: $table.schoolName, builder: (column) => column);

  GeneratedColumn<String> get shortCode =>
      $composableBuilder(column: $table.shortCode, builder: (column) => column);

  GeneratedColumn<String> get logoUrl =>
      $composableBuilder(column: $table.logoUrl, builder: (column) => column);

  GeneratedColumn<String> get subscriptionTier => $composableBuilder(
      column: $table.subscriptionTier, builder: (column) => column);

  GeneratedColumn<String> get activeCurriculum => $composableBuilder(
      column: $table.activeCurriculum, builder: (column) => column);

  GeneratedColumn<String> get activeCurriculumVersion => $composableBuilder(
      column: $table.activeCurriculumVersion, builder: (column) => column);

  GeneratedColumn<int> get totalSeats => $composableBuilder(
      column: $table.totalSeats, builder: (column) => column);

  GeneratedColumn<String> get schoolMasterKeyWrapped => $composableBuilder(
      column: $table.schoolMasterKeyWrapped, builder: (column) => column);

  GeneratedColumn<String> get adminRecoveryEmail => $composableBuilder(
      column: $table.adminRecoveryEmail, builder: (column) => column);

  GeneratedColumn<bool> get adminRecoveryEmailVerified => $composableBuilder(
      column: $table.adminRecoveryEmailVerified, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get updateCounter => $composableBuilder(
      column: $table.updateCounter, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<String> get lastModifiedBy => $composableBuilder(
      column: $table.lastModifiedBy, builder: (column) => column);

  Expression<T> teachersRefs<T extends Object>(
      Expression<T> Function($$TeachersTableAnnotationComposer a) f) {
    final $$TeachersTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.localId,
        referencedTable: $db.teachers,
        getReferencedColumn: (t) => t.schoolLocalId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TeachersTableAnnotationComposer(
              $db: $db,
              $table: $db.teachers,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SchoolsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SchoolsTable,
    School,
    $$SchoolsTableFilterComposer,
    $$SchoolsTableOrderingComposer,
    $$SchoolsTableAnnotationComposer,
    $$SchoolsTableCreateCompanionBuilder,
    $$SchoolsTableUpdateCompanionBuilder,
    (School, $$SchoolsTableReferences),
    School,
    PrefetchHooks Function({bool teachersRefs})> {
  $$SchoolsTableTableManager(_$AppDatabase db, $SchoolsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SchoolsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SchoolsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SchoolsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> localId = const Value.absent(),
            Value<String?> serverId = const Value.absent(),
            Value<String> schoolName = const Value.absent(),
            Value<String> shortCode = const Value.absent(),
            Value<String?> logoUrl = const Value.absent(),
            Value<String> subscriptionTier = const Value.absent(),
            Value<String> activeCurriculum = const Value.absent(),
            Value<String?> activeCurriculumVersion = const Value.absent(),
            Value<int> totalSeats = const Value.absent(),
            Value<String?> schoolMasterKeyWrapped = const Value.absent(),
            Value<String?> adminRecoveryEmail = const Value.absent(),
            Value<bool> adminRecoveryEmailVerified = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> updateCounter = const Value.absent(),
            Value<bool> isDeleted = const Value.absent(),
            Value<String?> lastModifiedBy = const Value.absent(),
          }) =>
              SchoolsCompanion(
            localId: localId,
            serverId: serverId,
            schoolName: schoolName,
            shortCode: shortCode,
            logoUrl: logoUrl,
            subscriptionTier: subscriptionTier,
            activeCurriculum: activeCurriculum,
            activeCurriculumVersion: activeCurriculumVersion,
            totalSeats: totalSeats,
            schoolMasterKeyWrapped: schoolMasterKeyWrapped,
            adminRecoveryEmail: adminRecoveryEmail,
            adminRecoveryEmailVerified: adminRecoveryEmailVerified,
            createdAt: createdAt,
            updatedAt: updatedAt,
            updateCounter: updateCounter,
            isDeleted: isDeleted,
            lastModifiedBy: lastModifiedBy,
          ),
          createCompanionCallback: ({
            Value<int> localId = const Value.absent(),
            Value<String?> serverId = const Value.absent(),
            required String schoolName,
            required String shortCode,
            Value<String?> logoUrl = const Value.absent(),
            Value<String> subscriptionTier = const Value.absent(),
            Value<String> activeCurriculum = const Value.absent(),
            Value<String?> activeCurriculumVersion = const Value.absent(),
            Value<int> totalSeats = const Value.absent(),
            Value<String?> schoolMasterKeyWrapped = const Value.absent(),
            Value<String?> adminRecoveryEmail = const Value.absent(),
            Value<bool> adminRecoveryEmailVerified = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> updateCounter = const Value.absent(),
            Value<bool> isDeleted = const Value.absent(),
            Value<String?> lastModifiedBy = const Value.absent(),
          }) =>
              SchoolsCompanion.insert(
            localId: localId,
            serverId: serverId,
            schoolName: schoolName,
            shortCode: shortCode,
            logoUrl: logoUrl,
            subscriptionTier: subscriptionTier,
            activeCurriculum: activeCurriculum,
            activeCurriculumVersion: activeCurriculumVersion,
            totalSeats: totalSeats,
            schoolMasterKeyWrapped: schoolMasterKeyWrapped,
            adminRecoveryEmail: adminRecoveryEmail,
            adminRecoveryEmailVerified: adminRecoveryEmailVerified,
            createdAt: createdAt,
            updatedAt: updatedAt,
            updateCounter: updateCounter,
            isDeleted: isDeleted,
            lastModifiedBy: lastModifiedBy,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$SchoolsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({teachersRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (teachersRefs) db.teachers],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (teachersRefs)
                    await $_getPrefetchedData<School, $SchoolsTable, Teacher>(
                        currentTable: table,
                        referencedTable:
                            $$SchoolsTableReferences._teachersRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SchoolsTableReferences(db, table, p0)
                                .teachersRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.schoolLocalId == item.localId),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$SchoolsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SchoolsTable,
    School,
    $$SchoolsTableFilterComposer,
    $$SchoolsTableOrderingComposer,
    $$SchoolsTableAnnotationComposer,
    $$SchoolsTableCreateCompanionBuilder,
    $$SchoolsTableUpdateCompanionBuilder,
    (School, $$SchoolsTableReferences),
    School,
    PrefetchHooks Function({bool teachersRefs})>;
typedef $$TeachersTableCreateCompanionBuilder = TeachersCompanion Function({
  Value<int> localId,
  Value<String?> serverId,
  required String email,
  required String teacherName,
  Value<String> role,
  required int schoolLocalId,
  Value<String?> schoolServerId,
  Value<bool> isActive,
  Value<bool> forcePasswordReset,
  Value<int> passwordHashVersion,
  Value<String?> schoolKeyWrapped,
  Value<DateTime?> lastCreditRefillDate,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> updateCounter,
  Value<bool> isDeleted,
  Value<String?> salt,
  Value<String?> lastModifiedBy,
});
typedef $$TeachersTableUpdateCompanionBuilder = TeachersCompanion Function({
  Value<int> localId,
  Value<String?> serverId,
  Value<String> email,
  Value<String> teacherName,
  Value<String> role,
  Value<int> schoolLocalId,
  Value<String?> schoolServerId,
  Value<bool> isActive,
  Value<bool> forcePasswordReset,
  Value<int> passwordHashVersion,
  Value<String?> schoolKeyWrapped,
  Value<DateTime?> lastCreditRefillDate,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> updateCounter,
  Value<bool> isDeleted,
  Value<String?> salt,
  Value<String?> lastModifiedBy,
});

final class $$TeachersTableReferences
    extends BaseReferences<_$AppDatabase, $TeachersTable, Teacher> {
  $$TeachersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SchoolsTable _schoolLocalIdTable(_$AppDatabase db) =>
      db.schools.createAlias(
          $_aliasNameGenerator(db.teachers.schoolLocalId, db.schools.localId));

  $$SchoolsTableProcessedTableManager get schoolLocalId {
    final $_column = $_itemColumn<int>('school_local_id')!;

    final manager = $$SchoolsTableTableManager($_db, $_db.schools)
        .filter((f) => f.localId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_schoolLocalIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$TeacherSubjectsTable, List<TeacherSubject>>
      _teacherSubjectsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.teacherSubjects,
              aliasName: $_aliasNameGenerator(
                  db.teachers.localId, db.teacherSubjects.teacherLocalId));

  $$TeacherSubjectsTableProcessedTableManager get teacherSubjectsRefs {
    final manager = $$TeacherSubjectsTableTableManager(
            $_db, $_db.teacherSubjects)
        .filter((f) =>
            f.teacherLocalId.localId.sqlEquals($_itemColumn<int>('local_id')!));

    final cache =
        $_typedResult.readTableOrNull(_teacherSubjectsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$TeachersTableFilterComposer
    extends Composer<_$AppDatabase, $TeachersTable> {
  $$TeachersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get localId => $composableBuilder(
      column: $table.localId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get email => $composableBuilder(
      column: $table.email, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get teacherName => $composableBuilder(
      column: $table.teacherName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get schoolServerId => $composableBuilder(
      column: $table.schoolServerId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get forcePasswordReset => $composableBuilder(
      column: $table.forcePasswordReset,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get passwordHashVersion => $composableBuilder(
      column: $table.passwordHashVersion,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get schoolKeyWrapped => $composableBuilder(
      column: $table.schoolKeyWrapped,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastCreditRefillDate => $composableBuilder(
      column: $table.lastCreditRefillDate,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updateCounter => $composableBuilder(
      column: $table.updateCounter, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isDeleted => $composableBuilder(
      column: $table.isDeleted, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get salt => $composableBuilder(
      column: $table.salt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastModifiedBy => $composableBuilder(
      column: $table.lastModifiedBy,
      builder: (column) => ColumnFilters(column));

  $$SchoolsTableFilterComposer get schoolLocalId {
    final $$SchoolsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.schoolLocalId,
        referencedTable: $db.schools,
        getReferencedColumn: (t) => t.localId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SchoolsTableFilterComposer(
              $db: $db,
              $table: $db.schools,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> teacherSubjectsRefs(
      Expression<bool> Function($$TeacherSubjectsTableFilterComposer f) f) {
    final $$TeacherSubjectsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.localId,
        referencedTable: $db.teacherSubjects,
        getReferencedColumn: (t) => t.teacherLocalId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TeacherSubjectsTableFilterComposer(
              $db: $db,
              $table: $db.teacherSubjects,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$TeachersTableOrderingComposer
    extends Composer<_$AppDatabase, $TeachersTable> {
  $$TeachersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get localId => $composableBuilder(
      column: $table.localId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get email => $composableBuilder(
      column: $table.email, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get teacherName => $composableBuilder(
      column: $table.teacherName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get schoolServerId => $composableBuilder(
      column: $table.schoolServerId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get forcePasswordReset => $composableBuilder(
      column: $table.forcePasswordReset,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get passwordHashVersion => $composableBuilder(
      column: $table.passwordHashVersion,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get schoolKeyWrapped => $composableBuilder(
      column: $table.schoolKeyWrapped,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastCreditRefillDate => $composableBuilder(
      column: $table.lastCreditRefillDate,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updateCounter => $composableBuilder(
      column: $table.updateCounter,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
      column: $table.isDeleted, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get salt => $composableBuilder(
      column: $table.salt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastModifiedBy => $composableBuilder(
      column: $table.lastModifiedBy,
      builder: (column) => ColumnOrderings(column));

  $$SchoolsTableOrderingComposer get schoolLocalId {
    final $$SchoolsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.schoolLocalId,
        referencedTable: $db.schools,
        getReferencedColumn: (t) => t.localId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SchoolsTableOrderingComposer(
              $db: $db,
              $table: $db.schools,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TeachersTableAnnotationComposer
    extends Composer<_$AppDatabase, $TeachersTable> {
  $$TeachersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get teacherName => $composableBuilder(
      column: $table.teacherName, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get schoolServerId => $composableBuilder(
      column: $table.schoolServerId, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<bool> get forcePasswordReset => $composableBuilder(
      column: $table.forcePasswordReset, builder: (column) => column);

  GeneratedColumn<int> get passwordHashVersion => $composableBuilder(
      column: $table.passwordHashVersion, builder: (column) => column);

  GeneratedColumn<String> get schoolKeyWrapped => $composableBuilder(
      column: $table.schoolKeyWrapped, builder: (column) => column);

  GeneratedColumn<DateTime> get lastCreditRefillDate => $composableBuilder(
      column: $table.lastCreditRefillDate, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get updateCounter => $composableBuilder(
      column: $table.updateCounter, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<String> get salt =>
      $composableBuilder(column: $table.salt, builder: (column) => column);

  GeneratedColumn<String> get lastModifiedBy => $composableBuilder(
      column: $table.lastModifiedBy, builder: (column) => column);

  $$SchoolsTableAnnotationComposer get schoolLocalId {
    final $$SchoolsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.schoolLocalId,
        referencedTable: $db.schools,
        getReferencedColumn: (t) => t.localId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SchoolsTableAnnotationComposer(
              $db: $db,
              $table: $db.schools,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> teacherSubjectsRefs<T extends Object>(
      Expression<T> Function($$TeacherSubjectsTableAnnotationComposer a) f) {
    final $$TeacherSubjectsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.localId,
        referencedTable: $db.teacherSubjects,
        getReferencedColumn: (t) => t.teacherLocalId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TeacherSubjectsTableAnnotationComposer(
              $db: $db,
              $table: $db.teacherSubjects,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$TeachersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TeachersTable,
    Teacher,
    $$TeachersTableFilterComposer,
    $$TeachersTableOrderingComposer,
    $$TeachersTableAnnotationComposer,
    $$TeachersTableCreateCompanionBuilder,
    $$TeachersTableUpdateCompanionBuilder,
    (Teacher, $$TeachersTableReferences),
    Teacher,
    PrefetchHooks Function({bool schoolLocalId, bool teacherSubjectsRefs})> {
  $$TeachersTableTableManager(_$AppDatabase db, $TeachersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TeachersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TeachersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TeachersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> localId = const Value.absent(),
            Value<String?> serverId = const Value.absent(),
            Value<String> email = const Value.absent(),
            Value<String> teacherName = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<int> schoolLocalId = const Value.absent(),
            Value<String?> schoolServerId = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<bool> forcePasswordReset = const Value.absent(),
            Value<int> passwordHashVersion = const Value.absent(),
            Value<String?> schoolKeyWrapped = const Value.absent(),
            Value<DateTime?> lastCreditRefillDate = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> updateCounter = const Value.absent(),
            Value<bool> isDeleted = const Value.absent(),
            Value<String?> salt = const Value.absent(),
            Value<String?> lastModifiedBy = const Value.absent(),
          }) =>
              TeachersCompanion(
            localId: localId,
            serverId: serverId,
            email: email,
            teacherName: teacherName,
            role: role,
            schoolLocalId: schoolLocalId,
            schoolServerId: schoolServerId,
            isActive: isActive,
            forcePasswordReset: forcePasswordReset,
            passwordHashVersion: passwordHashVersion,
            schoolKeyWrapped: schoolKeyWrapped,
            lastCreditRefillDate: lastCreditRefillDate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            updateCounter: updateCounter,
            isDeleted: isDeleted,
            salt: salt,
            lastModifiedBy: lastModifiedBy,
          ),
          createCompanionCallback: ({
            Value<int> localId = const Value.absent(),
            Value<String?> serverId = const Value.absent(),
            required String email,
            required String teacherName,
            Value<String> role = const Value.absent(),
            required int schoolLocalId,
            Value<String?> schoolServerId = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<bool> forcePasswordReset = const Value.absent(),
            Value<int> passwordHashVersion = const Value.absent(),
            Value<String?> schoolKeyWrapped = const Value.absent(),
            Value<DateTime?> lastCreditRefillDate = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> updateCounter = const Value.absent(),
            Value<bool> isDeleted = const Value.absent(),
            Value<String?> salt = const Value.absent(),
            Value<String?> lastModifiedBy = const Value.absent(),
          }) =>
              TeachersCompanion.insert(
            localId: localId,
            serverId: serverId,
            email: email,
            teacherName: teacherName,
            role: role,
            schoolLocalId: schoolLocalId,
            schoolServerId: schoolServerId,
            isActive: isActive,
            forcePasswordReset: forcePasswordReset,
            passwordHashVersion: passwordHashVersion,
            schoolKeyWrapped: schoolKeyWrapped,
            lastCreditRefillDate: lastCreditRefillDate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            updateCounter: updateCounter,
            isDeleted: isDeleted,
            salt: salt,
            lastModifiedBy: lastModifiedBy,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$TeachersTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {schoolLocalId = false, teacherSubjectsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (teacherSubjectsRefs) db.teacherSubjects
              ],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (schoolLocalId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.schoolLocalId,
                    referencedTable:
                        $$TeachersTableReferences._schoolLocalIdTable(db),
                    referencedColumn: $$TeachersTableReferences
                        ._schoolLocalIdTable(db)
                        .localId,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (teacherSubjectsRefs)
                    await $_getPrefetchedData<Teacher, $TeachersTable,
                            TeacherSubject>(
                        currentTable: table,
                        referencedTable: $$TeachersTableReferences
                            ._teacherSubjectsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$TeachersTableReferences(db, table, p0)
                                .teacherSubjectsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.teacherLocalId == item.localId),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$TeachersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TeachersTable,
    Teacher,
    $$TeachersTableFilterComposer,
    $$TeachersTableOrderingComposer,
    $$TeachersTableAnnotationComposer,
    $$TeachersTableCreateCompanionBuilder,
    $$TeachersTableUpdateCompanionBuilder,
    (Teacher, $$TeachersTableReferences),
    Teacher,
    PrefetchHooks Function({bool schoolLocalId, bool teacherSubjectsRefs})>;
typedef $$SubjectsTableCreateCompanionBuilder = SubjectsCompanion Function({
  Value<int> id,
});
typedef $$SubjectsTableUpdateCompanionBuilder = SubjectsCompanion Function({
  Value<int> id,
});

final class $$SubjectsTableReferences
    extends BaseReferences<_$AppDatabase, $SubjectsTable, Subject> {
  $$SubjectsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TeacherSubjectsTable, List<TeacherSubject>>
      _teacherSubjectsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.teacherSubjects,
              aliasName: $_aliasNameGenerator(
                  db.subjects.id, db.teacherSubjects.subjectId));

  $$TeacherSubjectsTableProcessedTableManager get teacherSubjectsRefs {
    final manager =
        $$TeacherSubjectsTableTableManager($_db, $_db.teacherSubjects)
            .filter((f) => f.subjectId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_teacherSubjectsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$SubjectsTableFilterComposer
    extends Composer<_$AppDatabase, $SubjectsTable> {
  $$SubjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  Expression<bool> teacherSubjectsRefs(
      Expression<bool> Function($$TeacherSubjectsTableFilterComposer f) f) {
    final $$TeacherSubjectsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.teacherSubjects,
        getReferencedColumn: (t) => t.subjectId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TeacherSubjectsTableFilterComposer(
              $db: $db,
              $table: $db.teacherSubjects,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SubjectsTableOrderingComposer
    extends Composer<_$AppDatabase, $SubjectsTable> {
  $$SubjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));
}

class $$SubjectsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SubjectsTable> {
  $$SubjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  Expression<T> teacherSubjectsRefs<T extends Object>(
      Expression<T> Function($$TeacherSubjectsTableAnnotationComposer a) f) {
    final $$TeacherSubjectsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.teacherSubjects,
        getReferencedColumn: (t) => t.subjectId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TeacherSubjectsTableAnnotationComposer(
              $db: $db,
              $table: $db.teacherSubjects,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SubjectsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SubjectsTable,
    Subject,
    $$SubjectsTableFilterComposer,
    $$SubjectsTableOrderingComposer,
    $$SubjectsTableAnnotationComposer,
    $$SubjectsTableCreateCompanionBuilder,
    $$SubjectsTableUpdateCompanionBuilder,
    (Subject, $$SubjectsTableReferences),
    Subject,
    PrefetchHooks Function({bool teacherSubjectsRefs})> {
  $$SubjectsTableTableManager(_$AppDatabase db, $SubjectsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SubjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SubjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SubjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
          }) =>
              SubjectsCompanion(
            id: id,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
          }) =>
              SubjectsCompanion.insert(
            id: id,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$SubjectsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({teacherSubjectsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (teacherSubjectsRefs) db.teacherSubjects
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (teacherSubjectsRefs)
                    await $_getPrefetchedData<Subject, $SubjectsTable,
                            TeacherSubject>(
                        currentTable: table,
                        referencedTable: $$SubjectsTableReferences
                            ._teacherSubjectsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SubjectsTableReferences(db, table, p0)
                                .teacherSubjectsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.subjectId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$SubjectsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SubjectsTable,
    Subject,
    $$SubjectsTableFilterComposer,
    $$SubjectsTableOrderingComposer,
    $$SubjectsTableAnnotationComposer,
    $$SubjectsTableCreateCompanionBuilder,
    $$SubjectsTableUpdateCompanionBuilder,
    (Subject, $$SubjectsTableReferences),
    Subject,
    PrefetchHooks Function({bool teacherSubjectsRefs})>;
typedef $$LessonsTableCreateCompanionBuilder = LessonsCompanion Function({
  Value<int> id,
  required String subject,
  required String classLevel,
  required int week,
  required String topic,
  required String difficulty,
  required String bloomsVerbs,
  required String curriculum,
  required String content,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$LessonsTableUpdateCompanionBuilder = LessonsCompanion Function({
  Value<int> id,
  Value<String> subject,
  Value<String> classLevel,
  Value<int> week,
  Value<String> topic,
  Value<String> difficulty,
  Value<String> bloomsVerbs,
  Value<String> curriculum,
  Value<String> content,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

class $$LessonsTableFilterComposer
    extends Composer<_$AppDatabase, $LessonsTable> {
  $$LessonsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get subject => $composableBuilder(
      column: $table.subject, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get classLevel => $composableBuilder(
      column: $table.classLevel, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get week => $composableBuilder(
      column: $table.week, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get topic => $composableBuilder(
      column: $table.topic, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get difficulty => $composableBuilder(
      column: $table.difficulty, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get bloomsVerbs => $composableBuilder(
      column: $table.bloomsVerbs, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get curriculum => $composableBuilder(
      column: $table.curriculum, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$LessonsTableOrderingComposer
    extends Composer<_$AppDatabase, $LessonsTable> {
  $$LessonsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get subject => $composableBuilder(
      column: $table.subject, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get classLevel => $composableBuilder(
      column: $table.classLevel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get week => $composableBuilder(
      column: $table.week, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get topic => $composableBuilder(
      column: $table.topic, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get difficulty => $composableBuilder(
      column: $table.difficulty, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get bloomsVerbs => $composableBuilder(
      column: $table.bloomsVerbs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get curriculum => $composableBuilder(
      column: $table.curriculum, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$LessonsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LessonsTable> {
  $$LessonsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get classLevel => $composableBuilder(
      column: $table.classLevel, builder: (column) => column);

  GeneratedColumn<int> get week =>
      $composableBuilder(column: $table.week, builder: (column) => column);

  GeneratedColumn<String> get topic =>
      $composableBuilder(column: $table.topic, builder: (column) => column);

  GeneratedColumn<String> get difficulty => $composableBuilder(
      column: $table.difficulty, builder: (column) => column);

  GeneratedColumn<String> get bloomsVerbs => $composableBuilder(
      column: $table.bloomsVerbs, builder: (column) => column);

  GeneratedColumn<String> get curriculum => $composableBuilder(
      column: $table.curriculum, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LessonsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LessonsTable,
    Lesson,
    $$LessonsTableFilterComposer,
    $$LessonsTableOrderingComposer,
    $$LessonsTableAnnotationComposer,
    $$LessonsTableCreateCompanionBuilder,
    $$LessonsTableUpdateCompanionBuilder,
    (Lesson, BaseReferences<_$AppDatabase, $LessonsTable, Lesson>),
    Lesson,
    PrefetchHooks Function()> {
  $$LessonsTableTableManager(_$AppDatabase db, $LessonsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LessonsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LessonsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LessonsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> subject = const Value.absent(),
            Value<String> classLevel = const Value.absent(),
            Value<int> week = const Value.absent(),
            Value<String> topic = const Value.absent(),
            Value<String> difficulty = const Value.absent(),
            Value<String> bloomsVerbs = const Value.absent(),
            Value<String> curriculum = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              LessonsCompanion(
            id: id,
            subject: subject,
            classLevel: classLevel,
            week: week,
            topic: topic,
            difficulty: difficulty,
            bloomsVerbs: bloomsVerbs,
            curriculum: curriculum,
            content: content,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String subject,
            required String classLevel,
            required int week,
            required String topic,
            required String difficulty,
            required String bloomsVerbs,
            required String curriculum,
            required String content,
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              LessonsCompanion.insert(
            id: id,
            subject: subject,
            classLevel: classLevel,
            week: week,
            topic: topic,
            difficulty: difficulty,
            bloomsVerbs: bloomsVerbs,
            curriculum: curriculum,
            content: content,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LessonsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LessonsTable,
    Lesson,
    $$LessonsTableFilterComposer,
    $$LessonsTableOrderingComposer,
    $$LessonsTableAnnotationComposer,
    $$LessonsTableCreateCompanionBuilder,
    $$LessonsTableUpdateCompanionBuilder,
    (Lesson, BaseReferences<_$AppDatabase, $LessonsTable, Lesson>),
    Lesson,
    PrefetchHooks Function()>;
typedef $$SchemeOfWorkTableCreateCompanionBuilder = SchemeOfWorkCompanion
    Function({
  Value<int> id,
});
typedef $$SchemeOfWorkTableUpdateCompanionBuilder = SchemeOfWorkCompanion
    Function({
  Value<int> id,
});

class $$SchemeOfWorkTableFilterComposer
    extends Composer<_$AppDatabase, $SchemeOfWorkTable> {
  $$SchemeOfWorkTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));
}

class $$SchemeOfWorkTableOrderingComposer
    extends Composer<_$AppDatabase, $SchemeOfWorkTable> {
  $$SchemeOfWorkTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));
}

class $$SchemeOfWorkTableAnnotationComposer
    extends Composer<_$AppDatabase, $SchemeOfWorkTable> {
  $$SchemeOfWorkTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);
}

class $$SchemeOfWorkTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SchemeOfWorkTable,
    SchemeOfWorkData,
    $$SchemeOfWorkTableFilterComposer,
    $$SchemeOfWorkTableOrderingComposer,
    $$SchemeOfWorkTableAnnotationComposer,
    $$SchemeOfWorkTableCreateCompanionBuilder,
    $$SchemeOfWorkTableUpdateCompanionBuilder,
    (
      SchemeOfWorkData,
      BaseReferences<_$AppDatabase, $SchemeOfWorkTable, SchemeOfWorkData>
    ),
    SchemeOfWorkData,
    PrefetchHooks Function()> {
  $$SchemeOfWorkTableTableManager(_$AppDatabase db, $SchemeOfWorkTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SchemeOfWorkTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SchemeOfWorkTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SchemeOfWorkTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
          }) =>
              SchemeOfWorkCompanion(
            id: id,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
          }) =>
              SchemeOfWorkCompanion.insert(
            id: id,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SchemeOfWorkTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SchemeOfWorkTable,
    SchemeOfWorkData,
    $$SchemeOfWorkTableFilterComposer,
    $$SchemeOfWorkTableOrderingComposer,
    $$SchemeOfWorkTableAnnotationComposer,
    $$SchemeOfWorkTableCreateCompanionBuilder,
    $$SchemeOfWorkTableUpdateCompanionBuilder,
    (
      SchemeOfWorkData,
      BaseReferences<_$AppDatabase, $SchemeOfWorkTable, SchemeOfWorkData>
    ),
    SchemeOfWorkData,
    PrefetchHooks Function()>;
typedef $$ExamsTableCreateCompanionBuilder = ExamsCompanion Function({
  Value<int> id,
  required String subject,
  required String classLevel,
  required String topic,
  required String difficulty,
  required String curriculum,
  required String content,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$ExamsTableUpdateCompanionBuilder = ExamsCompanion Function({
  Value<int> id,
  Value<String> subject,
  Value<String> classLevel,
  Value<String> topic,
  Value<String> difficulty,
  Value<String> curriculum,
  Value<String> content,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

class $$ExamsTableFilterComposer extends Composer<_$AppDatabase, $ExamsTable> {
  $$ExamsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get subject => $composableBuilder(
      column: $table.subject, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get classLevel => $composableBuilder(
      column: $table.classLevel, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get topic => $composableBuilder(
      column: $table.topic, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get difficulty => $composableBuilder(
      column: $table.difficulty, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get curriculum => $composableBuilder(
      column: $table.curriculum, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$ExamsTableOrderingComposer
    extends Composer<_$AppDatabase, $ExamsTable> {
  $$ExamsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get subject => $composableBuilder(
      column: $table.subject, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get classLevel => $composableBuilder(
      column: $table.classLevel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get topic => $composableBuilder(
      column: $table.topic, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get difficulty => $composableBuilder(
      column: $table.difficulty, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get curriculum => $composableBuilder(
      column: $table.curriculum, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$ExamsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExamsTable> {
  $$ExamsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get classLevel => $composableBuilder(
      column: $table.classLevel, builder: (column) => column);

  GeneratedColumn<String> get topic =>
      $composableBuilder(column: $table.topic, builder: (column) => column);

  GeneratedColumn<String> get difficulty => $composableBuilder(
      column: $table.difficulty, builder: (column) => column);

  GeneratedColumn<String> get curriculum => $composableBuilder(
      column: $table.curriculum, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ExamsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ExamsTable,
    Exam,
    $$ExamsTableFilterComposer,
    $$ExamsTableOrderingComposer,
    $$ExamsTableAnnotationComposer,
    $$ExamsTableCreateCompanionBuilder,
    $$ExamsTableUpdateCompanionBuilder,
    (Exam, BaseReferences<_$AppDatabase, $ExamsTable, Exam>),
    Exam,
    PrefetchHooks Function()> {
  $$ExamsTableTableManager(_$AppDatabase db, $ExamsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExamsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExamsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExamsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> subject = const Value.absent(),
            Value<String> classLevel = const Value.absent(),
            Value<String> topic = const Value.absent(),
            Value<String> difficulty = const Value.absent(),
            Value<String> curriculum = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              ExamsCompanion(
            id: id,
            subject: subject,
            classLevel: classLevel,
            topic: topic,
            difficulty: difficulty,
            curriculum: curriculum,
            content: content,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String subject,
            required String classLevel,
            required String topic,
            required String difficulty,
            required String curriculum,
            required String content,
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              ExamsCompanion.insert(
            id: id,
            subject: subject,
            classLevel: classLevel,
            topic: topic,
            difficulty: difficulty,
            curriculum: curriculum,
            content: content,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ExamsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ExamsTable,
    Exam,
    $$ExamsTableFilterComposer,
    $$ExamsTableOrderingComposer,
    $$ExamsTableAnnotationComposer,
    $$ExamsTableCreateCompanionBuilder,
    $$ExamsTableUpdateCompanionBuilder,
    (Exam, BaseReferences<_$AppDatabase, $ExamsTable, Exam>),
    Exam,
    PrefetchHooks Function()>;
typedef $$ProgressLogsTableCreateCompanionBuilder = ProgressLogsCompanion
    Function({
  Value<int> id,
});
typedef $$ProgressLogsTableUpdateCompanionBuilder = ProgressLogsCompanion
    Function({
  Value<int> id,
});

class $$ProgressLogsTableFilterComposer
    extends Composer<_$AppDatabase, $ProgressLogsTable> {
  $$ProgressLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));
}

class $$ProgressLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProgressLogsTable> {
  $$ProgressLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));
}

class $$ProgressLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProgressLogsTable> {
  $$ProgressLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);
}

class $$ProgressLogsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ProgressLogsTable,
    ProgressLog,
    $$ProgressLogsTableFilterComposer,
    $$ProgressLogsTableOrderingComposer,
    $$ProgressLogsTableAnnotationComposer,
    $$ProgressLogsTableCreateCompanionBuilder,
    $$ProgressLogsTableUpdateCompanionBuilder,
    (
      ProgressLog,
      BaseReferences<_$AppDatabase, $ProgressLogsTable, ProgressLog>
    ),
    ProgressLog,
    PrefetchHooks Function()> {
  $$ProgressLogsTableTableManager(_$AppDatabase db, $ProgressLogsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProgressLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProgressLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProgressLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
          }) =>
              ProgressLogsCompanion(
            id: id,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
          }) =>
              ProgressLogsCompanion.insert(
            id: id,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ProgressLogsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ProgressLogsTable,
    ProgressLog,
    $$ProgressLogsTableFilterComposer,
    $$ProgressLogsTableOrderingComposer,
    $$ProgressLogsTableAnnotationComposer,
    $$ProgressLogsTableCreateCompanionBuilder,
    $$ProgressLogsTableUpdateCompanionBuilder,
    (
      ProgressLog,
      BaseReferences<_$AppDatabase, $ProgressLogsTable, ProgressLog>
    ),
    ProgressLog,
    PrefetchHooks Function()>;
typedef $$VaultItemsTableCreateCompanionBuilder = VaultItemsCompanion Function({
  Value<int> id,
  Value<String?> serverId,
  required String title,
  required String description,
  required String subject,
  required String classLevel,
  required String curriculum,
  required String content,
  required String authorTeacherId,
  required String authorName,
  Value<String> minTier,
  Value<int> creditCost,
  Value<bool> needsApproval,
  Value<String> approvalStatus,
  Value<String?> rejectionReason,
  Value<String?> thumbnailUrl,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> updateCounter,
  Value<bool> isDeleted,
  Value<DateTime?> acquisitionDate,
  Value<String?> creditSpentBatchId,
});
typedef $$VaultItemsTableUpdateCompanionBuilder = VaultItemsCompanion Function({
  Value<int> id,
  Value<String?> serverId,
  Value<String> title,
  Value<String> description,
  Value<String> subject,
  Value<String> classLevel,
  Value<String> curriculum,
  Value<String> content,
  Value<String> authorTeacherId,
  Value<String> authorName,
  Value<String> minTier,
  Value<int> creditCost,
  Value<bool> needsApproval,
  Value<String> approvalStatus,
  Value<String?> rejectionReason,
  Value<String?> thumbnailUrl,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> updateCounter,
  Value<bool> isDeleted,
  Value<DateTime?> acquisitionDate,
  Value<String?> creditSpentBatchId,
});

class $$VaultItemsTableFilterComposer
    extends Composer<_$AppDatabase, $VaultItemsTable> {
  $$VaultItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get subject => $composableBuilder(
      column: $table.subject, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get classLevel => $composableBuilder(
      column: $table.classLevel, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get curriculum => $composableBuilder(
      column: $table.curriculum, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get authorTeacherId => $composableBuilder(
      column: $table.authorTeacherId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get authorName => $composableBuilder(
      column: $table.authorName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get minTier => $composableBuilder(
      column: $table.minTier, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get creditCost => $composableBuilder(
      column: $table.creditCost, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get needsApproval => $composableBuilder(
      column: $table.needsApproval, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get approvalStatus => $composableBuilder(
      column: $table.approvalStatus,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rejectionReason => $composableBuilder(
      column: $table.rejectionReason,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get thumbnailUrl => $composableBuilder(
      column: $table.thumbnailUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updateCounter => $composableBuilder(
      column: $table.updateCounter, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isDeleted => $composableBuilder(
      column: $table.isDeleted, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get acquisitionDate => $composableBuilder(
      column: $table.acquisitionDate,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get creditSpentBatchId => $composableBuilder(
      column: $table.creditSpentBatchId,
      builder: (column) => ColumnFilters(column));
}

class $$VaultItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $VaultItemsTable> {
  $$VaultItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get subject => $composableBuilder(
      column: $table.subject, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get classLevel => $composableBuilder(
      column: $table.classLevel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get curriculum => $composableBuilder(
      column: $table.curriculum, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get authorTeacherId => $composableBuilder(
      column: $table.authorTeacherId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get authorName => $composableBuilder(
      column: $table.authorName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get minTier => $composableBuilder(
      column: $table.minTier, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get creditCost => $composableBuilder(
      column: $table.creditCost, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get needsApproval => $composableBuilder(
      column: $table.needsApproval,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get approvalStatus => $composableBuilder(
      column: $table.approvalStatus,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rejectionReason => $composableBuilder(
      column: $table.rejectionReason,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get thumbnailUrl => $composableBuilder(
      column: $table.thumbnailUrl,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updateCounter => $composableBuilder(
      column: $table.updateCounter,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
      column: $table.isDeleted, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get acquisitionDate => $composableBuilder(
      column: $table.acquisitionDate,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get creditSpentBatchId => $composableBuilder(
      column: $table.creditSpentBatchId,
      builder: (column) => ColumnOrderings(column));
}

class $$VaultItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VaultItemsTable> {
  $$VaultItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get classLevel => $composableBuilder(
      column: $table.classLevel, builder: (column) => column);

  GeneratedColumn<String> get curriculum => $composableBuilder(
      column: $table.curriculum, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get authorTeacherId => $composableBuilder(
      column: $table.authorTeacherId, builder: (column) => column);

  GeneratedColumn<String> get authorName => $composableBuilder(
      column: $table.authorName, builder: (column) => column);

  GeneratedColumn<String> get minTier =>
      $composableBuilder(column: $table.minTier, builder: (column) => column);

  GeneratedColumn<int> get creditCost => $composableBuilder(
      column: $table.creditCost, builder: (column) => column);

  GeneratedColumn<bool> get needsApproval => $composableBuilder(
      column: $table.needsApproval, builder: (column) => column);

  GeneratedColumn<String> get approvalStatus => $composableBuilder(
      column: $table.approvalStatus, builder: (column) => column);

  GeneratedColumn<String> get rejectionReason => $composableBuilder(
      column: $table.rejectionReason, builder: (column) => column);

  GeneratedColumn<String> get thumbnailUrl => $composableBuilder(
      column: $table.thumbnailUrl, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get updateCounter => $composableBuilder(
      column: $table.updateCounter, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get acquisitionDate => $composableBuilder(
      column: $table.acquisitionDate, builder: (column) => column);

  GeneratedColumn<String> get creditSpentBatchId => $composableBuilder(
      column: $table.creditSpentBatchId, builder: (column) => column);
}

class $$VaultItemsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $VaultItemsTable,
    VaultItem,
    $$VaultItemsTableFilterComposer,
    $$VaultItemsTableOrderingComposer,
    $$VaultItemsTableAnnotationComposer,
    $$VaultItemsTableCreateCompanionBuilder,
    $$VaultItemsTableUpdateCompanionBuilder,
    (VaultItem, BaseReferences<_$AppDatabase, $VaultItemsTable, VaultItem>),
    VaultItem,
    PrefetchHooks Function()> {
  $$VaultItemsTableTableManager(_$AppDatabase db, $VaultItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VaultItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VaultItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VaultItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> serverId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<String> subject = const Value.absent(),
            Value<String> classLevel = const Value.absent(),
            Value<String> curriculum = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<String> authorTeacherId = const Value.absent(),
            Value<String> authorName = const Value.absent(),
            Value<String> minTier = const Value.absent(),
            Value<int> creditCost = const Value.absent(),
            Value<bool> needsApproval = const Value.absent(),
            Value<String> approvalStatus = const Value.absent(),
            Value<String?> rejectionReason = const Value.absent(),
            Value<String?> thumbnailUrl = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> updateCounter = const Value.absent(),
            Value<bool> isDeleted = const Value.absent(),
            Value<DateTime?> acquisitionDate = const Value.absent(),
            Value<String?> creditSpentBatchId = const Value.absent(),
          }) =>
              VaultItemsCompanion(
            id: id,
            serverId: serverId,
            title: title,
            description: description,
            subject: subject,
            classLevel: classLevel,
            curriculum: curriculum,
            content: content,
            authorTeacherId: authorTeacherId,
            authorName: authorName,
            minTier: minTier,
            creditCost: creditCost,
            needsApproval: needsApproval,
            approvalStatus: approvalStatus,
            rejectionReason: rejectionReason,
            thumbnailUrl: thumbnailUrl,
            createdAt: createdAt,
            updatedAt: updatedAt,
            updateCounter: updateCounter,
            isDeleted: isDeleted,
            acquisitionDate: acquisitionDate,
            creditSpentBatchId: creditSpentBatchId,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> serverId = const Value.absent(),
            required String title,
            required String description,
            required String subject,
            required String classLevel,
            required String curriculum,
            required String content,
            required String authorTeacherId,
            required String authorName,
            Value<String> minTier = const Value.absent(),
            Value<int> creditCost = const Value.absent(),
            Value<bool> needsApproval = const Value.absent(),
            Value<String> approvalStatus = const Value.absent(),
            Value<String?> rejectionReason = const Value.absent(),
            Value<String?> thumbnailUrl = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> updateCounter = const Value.absent(),
            Value<bool> isDeleted = const Value.absent(),
            Value<DateTime?> acquisitionDate = const Value.absent(),
            Value<String?> creditSpentBatchId = const Value.absent(),
          }) =>
              VaultItemsCompanion.insert(
            id: id,
            serverId: serverId,
            title: title,
            description: description,
            subject: subject,
            classLevel: classLevel,
            curriculum: curriculum,
            content: content,
            authorTeacherId: authorTeacherId,
            authorName: authorName,
            minTier: minTier,
            creditCost: creditCost,
            needsApproval: needsApproval,
            approvalStatus: approvalStatus,
            rejectionReason: rejectionReason,
            thumbnailUrl: thumbnailUrl,
            createdAt: createdAt,
            updatedAt: updatedAt,
            updateCounter: updateCounter,
            isDeleted: isDeleted,
            acquisitionDate: acquisitionDate,
            creditSpentBatchId: creditSpentBatchId,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$VaultItemsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $VaultItemsTable,
    VaultItem,
    $$VaultItemsTableFilterComposer,
    $$VaultItemsTableOrderingComposer,
    $$VaultItemsTableAnnotationComposer,
    $$VaultItemsTableCreateCompanionBuilder,
    $$VaultItemsTableUpdateCompanionBuilder,
    (VaultItem, BaseReferences<_$AppDatabase, $VaultItemsTable, VaultItem>),
    VaultItem,
    PrefetchHooks Function()>;
typedef $$SecurityConfigTableCreateCompanionBuilder = SecurityConfigCompanion
    Function({
  Value<int> id,
  Value<bool> isLocked,
  Value<DateTime> lastSeenTime,
  Value<DateTime?> lastKnownGoodTime,
  Value<double?> monotonicLastSeen,
  Value<int> offlineCredits,
  Value<String> creditSpentIdsLocal,
  Value<int> creditServerCounter,
  Value<String?> creditSpentBatchId,
  Value<DateTime?> lastCreditRefillServerTime,
  Value<DateTime?> lastPullTimestamp,
  Value<String?> syncCursor,
  Value<DateTime?> lastSyncAttemptTime,
  Value<DateTime?> syncCooldownUntil,
  Value<int> lastRealtimeEventId,
  Value<DateTime?> heartbeatLastSuccess,
  Value<DateTime?> lastVacuumDate,
  Value<String?> encryptionKeyWrapped,
  Value<bool> encryptionRecoveryNeeded,
  Value<String> corruptedRecordIds,
  Value<int> lastKnownPasswordHashVersion,
  Value<String?> sessionKeyEncrypted,
  Value<DateTime?> sessionKeyExpiry,
  Value<bool> syncPendingAfterBiometricTimeout,
  required String currentDeviceId,
  Value<bool> pendingDbReplacement,
  Value<String?> vacuumedDbPath,
});
typedef $$SecurityConfigTableUpdateCompanionBuilder = SecurityConfigCompanion
    Function({
  Value<int> id,
  Value<bool> isLocked,
  Value<DateTime> lastSeenTime,
  Value<DateTime?> lastKnownGoodTime,
  Value<double?> monotonicLastSeen,
  Value<int> offlineCredits,
  Value<String> creditSpentIdsLocal,
  Value<int> creditServerCounter,
  Value<String?> creditSpentBatchId,
  Value<DateTime?> lastCreditRefillServerTime,
  Value<DateTime?> lastPullTimestamp,
  Value<String?> syncCursor,
  Value<DateTime?> lastSyncAttemptTime,
  Value<DateTime?> syncCooldownUntil,
  Value<int> lastRealtimeEventId,
  Value<DateTime?> heartbeatLastSuccess,
  Value<DateTime?> lastVacuumDate,
  Value<String?> encryptionKeyWrapped,
  Value<bool> encryptionRecoveryNeeded,
  Value<String> corruptedRecordIds,
  Value<int> lastKnownPasswordHashVersion,
  Value<String?> sessionKeyEncrypted,
  Value<DateTime?> sessionKeyExpiry,
  Value<bool> syncPendingAfterBiometricTimeout,
  Value<String> currentDeviceId,
  Value<bool> pendingDbReplacement,
  Value<String?> vacuumedDbPath,
});

class $$SecurityConfigTableFilterComposer
    extends Composer<_$AppDatabase, $SecurityConfigTable> {
  $$SecurityConfigTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isLocked => $composableBuilder(
      column: $table.isLocked, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastSeenTime => $composableBuilder(
      column: $table.lastSeenTime, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastKnownGoodTime => $composableBuilder(
      column: $table.lastKnownGoodTime,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get monotonicLastSeen => $composableBuilder(
      column: $table.monotonicLastSeen,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get offlineCredits => $composableBuilder(
      column: $table.offlineCredits,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get creditSpentIdsLocal => $composableBuilder(
      column: $table.creditSpentIdsLocal,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get creditServerCounter => $composableBuilder(
      column: $table.creditServerCounter,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get creditSpentBatchId => $composableBuilder(
      column: $table.creditSpentBatchId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastCreditRefillServerTime => $composableBuilder(
      column: $table.lastCreditRefillServerTime,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastPullTimestamp => $composableBuilder(
      column: $table.lastPullTimestamp,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncCursor => $composableBuilder(
      column: $table.syncCursor, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastSyncAttemptTime => $composableBuilder(
      column: $table.lastSyncAttemptTime,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get syncCooldownUntil => $composableBuilder(
      column: $table.syncCooldownUntil,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastRealtimeEventId => $composableBuilder(
      column: $table.lastRealtimeEventId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get heartbeatLastSuccess => $composableBuilder(
      column: $table.heartbeatLastSuccess,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastVacuumDate => $composableBuilder(
      column: $table.lastVacuumDate,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get encryptionKeyWrapped => $composableBuilder(
      column: $table.encryptionKeyWrapped,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get encryptionRecoveryNeeded => $composableBuilder(
      column: $table.encryptionRecoveryNeeded,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get corruptedRecordIds => $composableBuilder(
      column: $table.corruptedRecordIds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastKnownPasswordHashVersion => $composableBuilder(
      column: $table.lastKnownPasswordHashVersion,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sessionKeyEncrypted => $composableBuilder(
      column: $table.sessionKeyEncrypted,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get sessionKeyExpiry => $composableBuilder(
      column: $table.sessionKeyExpiry,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get syncPendingAfterBiometricTimeout =>
      $composableBuilder(
          column: $table.syncPendingAfterBiometricTimeout,
          builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get currentDeviceId => $composableBuilder(
      column: $table.currentDeviceId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get pendingDbReplacement => $composableBuilder(
      column: $table.pendingDbReplacement,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get vacuumedDbPath => $composableBuilder(
      column: $table.vacuumedDbPath,
      builder: (column) => ColumnFilters(column));
}

class $$SecurityConfigTableOrderingComposer
    extends Composer<_$AppDatabase, $SecurityConfigTable> {
  $$SecurityConfigTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isLocked => $composableBuilder(
      column: $table.isLocked, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastSeenTime => $composableBuilder(
      column: $table.lastSeenTime,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastKnownGoodTime => $composableBuilder(
      column: $table.lastKnownGoodTime,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get monotonicLastSeen => $composableBuilder(
      column: $table.monotonicLastSeen,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get offlineCredits => $composableBuilder(
      column: $table.offlineCredits,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get creditSpentIdsLocal => $composableBuilder(
      column: $table.creditSpentIdsLocal,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get creditServerCounter => $composableBuilder(
      column: $table.creditServerCounter,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get creditSpentBatchId => $composableBuilder(
      column: $table.creditSpentBatchId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastCreditRefillServerTime =>
      $composableBuilder(
          column: $table.lastCreditRefillServerTime,
          builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastPullTimestamp => $composableBuilder(
      column: $table.lastPullTimestamp,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncCursor => $composableBuilder(
      column: $table.syncCursor, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastSyncAttemptTime => $composableBuilder(
      column: $table.lastSyncAttemptTime,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get syncCooldownUntil => $composableBuilder(
      column: $table.syncCooldownUntil,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastRealtimeEventId => $composableBuilder(
      column: $table.lastRealtimeEventId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get heartbeatLastSuccess => $composableBuilder(
      column: $table.heartbeatLastSuccess,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastVacuumDate => $composableBuilder(
      column: $table.lastVacuumDate,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get encryptionKeyWrapped => $composableBuilder(
      column: $table.encryptionKeyWrapped,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get encryptionRecoveryNeeded => $composableBuilder(
      column: $table.encryptionRecoveryNeeded,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get corruptedRecordIds => $composableBuilder(
      column: $table.corruptedRecordIds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastKnownPasswordHashVersion => $composableBuilder(
      column: $table.lastKnownPasswordHashVersion,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sessionKeyEncrypted => $composableBuilder(
      column: $table.sessionKeyEncrypted,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get sessionKeyExpiry => $composableBuilder(
      column: $table.sessionKeyExpiry,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get syncPendingAfterBiometricTimeout =>
      $composableBuilder(
          column: $table.syncPendingAfterBiometricTimeout,
          builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get currentDeviceId => $composableBuilder(
      column: $table.currentDeviceId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get pendingDbReplacement => $composableBuilder(
      column: $table.pendingDbReplacement,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get vacuumedDbPath => $composableBuilder(
      column: $table.vacuumedDbPath,
      builder: (column) => ColumnOrderings(column));
}

class $$SecurityConfigTableAnnotationComposer
    extends Composer<_$AppDatabase, $SecurityConfigTable> {
  $$SecurityConfigTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<bool> get isLocked =>
      $composableBuilder(column: $table.isLocked, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeenTime => $composableBuilder(
      column: $table.lastSeenTime, builder: (column) => column);

  GeneratedColumn<DateTime> get lastKnownGoodTime => $composableBuilder(
      column: $table.lastKnownGoodTime, builder: (column) => column);

  GeneratedColumn<double> get monotonicLastSeen => $composableBuilder(
      column: $table.monotonicLastSeen, builder: (column) => column);

  GeneratedColumn<int> get offlineCredits => $composableBuilder(
      column: $table.offlineCredits, builder: (column) => column);

  GeneratedColumn<String> get creditSpentIdsLocal => $composableBuilder(
      column: $table.creditSpentIdsLocal, builder: (column) => column);

  GeneratedColumn<int> get creditServerCounter => $composableBuilder(
      column: $table.creditServerCounter, builder: (column) => column);

  GeneratedColumn<String> get creditSpentBatchId => $composableBuilder(
      column: $table.creditSpentBatchId, builder: (column) => column);

  GeneratedColumn<DateTime> get lastCreditRefillServerTime =>
      $composableBuilder(
          column: $table.lastCreditRefillServerTime,
          builder: (column) => column);

  GeneratedColumn<DateTime> get lastPullTimestamp => $composableBuilder(
      column: $table.lastPullTimestamp, builder: (column) => column);

  GeneratedColumn<String> get syncCursor => $composableBuilder(
      column: $table.syncCursor, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncAttemptTime => $composableBuilder(
      column: $table.lastSyncAttemptTime, builder: (column) => column);

  GeneratedColumn<DateTime> get syncCooldownUntil => $composableBuilder(
      column: $table.syncCooldownUntil, builder: (column) => column);

  GeneratedColumn<int> get lastRealtimeEventId => $composableBuilder(
      column: $table.lastRealtimeEventId, builder: (column) => column);

  GeneratedColumn<DateTime> get heartbeatLastSuccess => $composableBuilder(
      column: $table.heartbeatLastSuccess, builder: (column) => column);

  GeneratedColumn<DateTime> get lastVacuumDate => $composableBuilder(
      column: $table.lastVacuumDate, builder: (column) => column);

  GeneratedColumn<String> get encryptionKeyWrapped => $composableBuilder(
      column: $table.encryptionKeyWrapped, builder: (column) => column);

  GeneratedColumn<bool> get encryptionRecoveryNeeded => $composableBuilder(
      column: $table.encryptionRecoveryNeeded, builder: (column) => column);

  GeneratedColumn<String> get corruptedRecordIds => $composableBuilder(
      column: $table.corruptedRecordIds, builder: (column) => column);

  GeneratedColumn<int> get lastKnownPasswordHashVersion => $composableBuilder(
      column: $table.lastKnownPasswordHashVersion, builder: (column) => column);

  GeneratedColumn<String> get sessionKeyEncrypted => $composableBuilder(
      column: $table.sessionKeyEncrypted, builder: (column) => column);

  GeneratedColumn<DateTime> get sessionKeyExpiry => $composableBuilder(
      column: $table.sessionKeyExpiry, builder: (column) => column);

  GeneratedColumn<bool> get syncPendingAfterBiometricTimeout =>
      $composableBuilder(
          column: $table.syncPendingAfterBiometricTimeout,
          builder: (column) => column);

  GeneratedColumn<String> get currentDeviceId => $composableBuilder(
      column: $table.currentDeviceId, builder: (column) => column);

  GeneratedColumn<bool> get pendingDbReplacement => $composableBuilder(
      column: $table.pendingDbReplacement, builder: (column) => column);

  GeneratedColumn<String> get vacuumedDbPath => $composableBuilder(
      column: $table.vacuumedDbPath, builder: (column) => column);
}

class $$SecurityConfigTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SecurityConfigTable,
    SecurityConfigData,
    $$SecurityConfigTableFilterComposer,
    $$SecurityConfigTableOrderingComposer,
    $$SecurityConfigTableAnnotationComposer,
    $$SecurityConfigTableCreateCompanionBuilder,
    $$SecurityConfigTableUpdateCompanionBuilder,
    (
      SecurityConfigData,
      BaseReferences<_$AppDatabase, $SecurityConfigTable, SecurityConfigData>
    ),
    SecurityConfigData,
    PrefetchHooks Function()> {
  $$SecurityConfigTableTableManager(
      _$AppDatabase db, $SecurityConfigTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SecurityConfigTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SecurityConfigTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SecurityConfigTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<bool> isLocked = const Value.absent(),
            Value<DateTime> lastSeenTime = const Value.absent(),
            Value<DateTime?> lastKnownGoodTime = const Value.absent(),
            Value<double?> monotonicLastSeen = const Value.absent(),
            Value<int> offlineCredits = const Value.absent(),
            Value<String> creditSpentIdsLocal = const Value.absent(),
            Value<int> creditServerCounter = const Value.absent(),
            Value<String?> creditSpentBatchId = const Value.absent(),
            Value<DateTime?> lastCreditRefillServerTime = const Value.absent(),
            Value<DateTime?> lastPullTimestamp = const Value.absent(),
            Value<String?> syncCursor = const Value.absent(),
            Value<DateTime?> lastSyncAttemptTime = const Value.absent(),
            Value<DateTime?> syncCooldownUntil = const Value.absent(),
            Value<int> lastRealtimeEventId = const Value.absent(),
            Value<DateTime?> heartbeatLastSuccess = const Value.absent(),
            Value<DateTime?> lastVacuumDate = const Value.absent(),
            Value<String?> encryptionKeyWrapped = const Value.absent(),
            Value<bool> encryptionRecoveryNeeded = const Value.absent(),
            Value<String> corruptedRecordIds = const Value.absent(),
            Value<int> lastKnownPasswordHashVersion = const Value.absent(),
            Value<String?> sessionKeyEncrypted = const Value.absent(),
            Value<DateTime?> sessionKeyExpiry = const Value.absent(),
            Value<bool> syncPendingAfterBiometricTimeout = const Value.absent(),
            Value<String> currentDeviceId = const Value.absent(),
            Value<bool> pendingDbReplacement = const Value.absent(),
            Value<String?> vacuumedDbPath = const Value.absent(),
          }) =>
              SecurityConfigCompanion(
            id: id,
            isLocked: isLocked,
            lastSeenTime: lastSeenTime,
            lastKnownGoodTime: lastKnownGoodTime,
            monotonicLastSeen: monotonicLastSeen,
            offlineCredits: offlineCredits,
            creditSpentIdsLocal: creditSpentIdsLocal,
            creditServerCounter: creditServerCounter,
            creditSpentBatchId: creditSpentBatchId,
            lastCreditRefillServerTime: lastCreditRefillServerTime,
            lastPullTimestamp: lastPullTimestamp,
            syncCursor: syncCursor,
            lastSyncAttemptTime: lastSyncAttemptTime,
            syncCooldownUntil: syncCooldownUntil,
            lastRealtimeEventId: lastRealtimeEventId,
            heartbeatLastSuccess: heartbeatLastSuccess,
            lastVacuumDate: lastVacuumDate,
            encryptionKeyWrapped: encryptionKeyWrapped,
            encryptionRecoveryNeeded: encryptionRecoveryNeeded,
            corruptedRecordIds: corruptedRecordIds,
            lastKnownPasswordHashVersion: lastKnownPasswordHashVersion,
            sessionKeyEncrypted: sessionKeyEncrypted,
            sessionKeyExpiry: sessionKeyExpiry,
            syncPendingAfterBiometricTimeout: syncPendingAfterBiometricTimeout,
            currentDeviceId: currentDeviceId,
            pendingDbReplacement: pendingDbReplacement,
            vacuumedDbPath: vacuumedDbPath,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<bool> isLocked = const Value.absent(),
            Value<DateTime> lastSeenTime = const Value.absent(),
            Value<DateTime?> lastKnownGoodTime = const Value.absent(),
            Value<double?> monotonicLastSeen = const Value.absent(),
            Value<int> offlineCredits = const Value.absent(),
            Value<String> creditSpentIdsLocal = const Value.absent(),
            Value<int> creditServerCounter = const Value.absent(),
            Value<String?> creditSpentBatchId = const Value.absent(),
            Value<DateTime?> lastCreditRefillServerTime = const Value.absent(),
            Value<DateTime?> lastPullTimestamp = const Value.absent(),
            Value<String?> syncCursor = const Value.absent(),
            Value<DateTime?> lastSyncAttemptTime = const Value.absent(),
            Value<DateTime?> syncCooldownUntil = const Value.absent(),
            Value<int> lastRealtimeEventId = const Value.absent(),
            Value<DateTime?> heartbeatLastSuccess = const Value.absent(),
            Value<DateTime?> lastVacuumDate = const Value.absent(),
            Value<String?> encryptionKeyWrapped = const Value.absent(),
            Value<bool> encryptionRecoveryNeeded = const Value.absent(),
            Value<String> corruptedRecordIds = const Value.absent(),
            Value<int> lastKnownPasswordHashVersion = const Value.absent(),
            Value<String?> sessionKeyEncrypted = const Value.absent(),
            Value<DateTime?> sessionKeyExpiry = const Value.absent(),
            Value<bool> syncPendingAfterBiometricTimeout = const Value.absent(),
            required String currentDeviceId,
            Value<bool> pendingDbReplacement = const Value.absent(),
            Value<String?> vacuumedDbPath = const Value.absent(),
          }) =>
              SecurityConfigCompanion.insert(
            id: id,
            isLocked: isLocked,
            lastSeenTime: lastSeenTime,
            lastKnownGoodTime: lastKnownGoodTime,
            monotonicLastSeen: monotonicLastSeen,
            offlineCredits: offlineCredits,
            creditSpentIdsLocal: creditSpentIdsLocal,
            creditServerCounter: creditServerCounter,
            creditSpentBatchId: creditSpentBatchId,
            lastCreditRefillServerTime: lastCreditRefillServerTime,
            lastPullTimestamp: lastPullTimestamp,
            syncCursor: syncCursor,
            lastSyncAttemptTime: lastSyncAttemptTime,
            syncCooldownUntil: syncCooldownUntil,
            lastRealtimeEventId: lastRealtimeEventId,
            heartbeatLastSuccess: heartbeatLastSuccess,
            lastVacuumDate: lastVacuumDate,
            encryptionKeyWrapped: encryptionKeyWrapped,
            encryptionRecoveryNeeded: encryptionRecoveryNeeded,
            corruptedRecordIds: corruptedRecordIds,
            lastKnownPasswordHashVersion: lastKnownPasswordHashVersion,
            sessionKeyEncrypted: sessionKeyEncrypted,
            sessionKeyExpiry: sessionKeyExpiry,
            syncPendingAfterBiometricTimeout: syncPendingAfterBiometricTimeout,
            currentDeviceId: currentDeviceId,
            pendingDbReplacement: pendingDbReplacement,
            vacuumedDbPath: vacuumedDbPath,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SecurityConfigTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SecurityConfigTable,
    SecurityConfigData,
    $$SecurityConfigTableFilterComposer,
    $$SecurityConfigTableOrderingComposer,
    $$SecurityConfigTableAnnotationComposer,
    $$SecurityConfigTableCreateCompanionBuilder,
    $$SecurityConfigTableUpdateCompanionBuilder,
    (
      SecurityConfigData,
      BaseReferences<_$AppDatabase, $SecurityConfigTable, SecurityConfigData>
    ),
    SecurityConfigData,
    PrefetchHooks Function()>;
typedef $$SyncQueueTableCreateCompanionBuilder = SyncQueueCompanion Function({
  Value<int> id,
  required String queueTable,
  required int recordLocalId,
  required String operation,
  required String payload,
  Value<int> attempts,
  Value<bool> isEmergency,
  Value<DateTime> createdAt,
  Value<DateTime?> lastAttemptAt,
});
typedef $$SyncQueueTableUpdateCompanionBuilder = SyncQueueCompanion Function({
  Value<int> id,
  Value<String> queueTable,
  Value<int> recordLocalId,
  Value<String> operation,
  Value<String> payload,
  Value<int> attempts,
  Value<bool> isEmergency,
  Value<DateTime> createdAt,
  Value<DateTime?> lastAttemptAt,
});

class $$SyncQueueTableFilterComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get queueTable => $composableBuilder(
      column: $table.queueTable, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get recordLocalId => $composableBuilder(
      column: $table.recordLocalId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get operation => $composableBuilder(
      column: $table.operation, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isEmergency => $composableBuilder(
      column: $table.isEmergency, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt, builder: (column) => ColumnFilters(column));
}

class $$SyncQueueTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get queueTable => $composableBuilder(
      column: $table.queueTable, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get recordLocalId => $composableBuilder(
      column: $table.recordLocalId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get operation => $composableBuilder(
      column: $table.operation, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isEmergency => $composableBuilder(
      column: $table.isEmergency, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt,
      builder: (column) => ColumnOrderings(column));
}

class $$SyncQueueTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get queueTable => $composableBuilder(
      column: $table.queueTable, builder: (column) => column);

  GeneratedColumn<int> get recordLocalId => $composableBuilder(
      column: $table.recordLocalId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<bool> get isEmergency => $composableBuilder(
      column: $table.isEmergency, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt, builder: (column) => column);
}

class $$SyncQueueTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncQueueTable,
    SyncQueueData,
    $$SyncQueueTableFilterComposer,
    $$SyncQueueTableOrderingComposer,
    $$SyncQueueTableAnnotationComposer,
    $$SyncQueueTableCreateCompanionBuilder,
    $$SyncQueueTableUpdateCompanionBuilder,
    (
      SyncQueueData,
      BaseReferences<_$AppDatabase, $SyncQueueTable, SyncQueueData>
    ),
    SyncQueueData,
    PrefetchHooks Function()> {
  $$SyncQueueTableTableManager(_$AppDatabase db, $SyncQueueTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncQueueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> queueTable = const Value.absent(),
            Value<int> recordLocalId = const Value.absent(),
            Value<String> operation = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<int> attempts = const Value.absent(),
            Value<bool> isEmergency = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> lastAttemptAt = const Value.absent(),
          }) =>
              SyncQueueCompanion(
            id: id,
            queueTable: queueTable,
            recordLocalId: recordLocalId,
            operation: operation,
            payload: payload,
            attempts: attempts,
            isEmergency: isEmergency,
            createdAt: createdAt,
            lastAttemptAt: lastAttemptAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String queueTable,
            required int recordLocalId,
            required String operation,
            required String payload,
            Value<int> attempts = const Value.absent(),
            Value<bool> isEmergency = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> lastAttemptAt = const Value.absent(),
          }) =>
              SyncQueueCompanion.insert(
            id: id,
            queueTable: queueTable,
            recordLocalId: recordLocalId,
            operation: operation,
            payload: payload,
            attempts: attempts,
            isEmergency: isEmergency,
            createdAt: createdAt,
            lastAttemptAt: lastAttemptAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncQueueTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncQueueTable,
    SyncQueueData,
    $$SyncQueueTableFilterComposer,
    $$SyncQueueTableOrderingComposer,
    $$SyncQueueTableAnnotationComposer,
    $$SyncQueueTableCreateCompanionBuilder,
    $$SyncQueueTableUpdateCompanionBuilder,
    (
      SyncQueueData,
      BaseReferences<_$AppDatabase, $SyncQueueTable, SyncQueueData>
    ),
    SyncQueueData,
    PrefetchHooks Function()>;
typedef $$SyncQueueSnapshotTableCreateCompanionBuilder
    = SyncQueueSnapshotCompanion Function({
  Value<int> id,
});
typedef $$SyncQueueSnapshotTableUpdateCompanionBuilder
    = SyncQueueSnapshotCompanion Function({
  Value<int> id,
});

class $$SyncQueueSnapshotTableFilterComposer
    extends Composer<_$AppDatabase, $SyncQueueSnapshotTable> {
  $$SyncQueueSnapshotTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));
}

class $$SyncQueueSnapshotTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncQueueSnapshotTable> {
  $$SyncQueueSnapshotTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));
}

class $$SyncQueueSnapshotTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncQueueSnapshotTable> {
  $$SyncQueueSnapshotTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);
}

class $$SyncQueueSnapshotTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncQueueSnapshotTable,
    SyncQueueSnapshotData,
    $$SyncQueueSnapshotTableFilterComposer,
    $$SyncQueueSnapshotTableOrderingComposer,
    $$SyncQueueSnapshotTableAnnotationComposer,
    $$SyncQueueSnapshotTableCreateCompanionBuilder,
    $$SyncQueueSnapshotTableUpdateCompanionBuilder,
    (
      SyncQueueSnapshotData,
      BaseReferences<_$AppDatabase, $SyncQueueSnapshotTable,
          SyncQueueSnapshotData>
    ),
    SyncQueueSnapshotData,
    PrefetchHooks Function()> {
  $$SyncQueueSnapshotTableTableManager(
      _$AppDatabase db, $SyncQueueSnapshotTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncQueueSnapshotTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncQueueSnapshotTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncQueueSnapshotTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
          }) =>
              SyncQueueSnapshotCompanion(
            id: id,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
          }) =>
              SyncQueueSnapshotCompanion.insert(
            id: id,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncQueueSnapshotTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncQueueSnapshotTable,
    SyncQueueSnapshotData,
    $$SyncQueueSnapshotTableFilterComposer,
    $$SyncQueueSnapshotTableOrderingComposer,
    $$SyncQueueSnapshotTableAnnotationComposer,
    $$SyncQueueSnapshotTableCreateCompanionBuilder,
    $$SyncQueueSnapshotTableUpdateCompanionBuilder,
    (
      SyncQueueSnapshotData,
      BaseReferences<_$AppDatabase, $SyncQueueSnapshotTable,
          SyncQueueSnapshotData>
    ),
    SyncQueueSnapshotData,
    PrefetchHooks Function()>;
typedef $$VersionHashesTableCreateCompanionBuilder = VersionHashesCompanion
    Function({
  Value<int> id,
  required String table,
  required int recordLocalId,
  required String hash,
  Value<String?> snapshotJson,
  required DateTime setAt,
});
typedef $$VersionHashesTableUpdateCompanionBuilder = VersionHashesCompanion
    Function({
  Value<int> id,
  Value<String> table,
  Value<int> recordLocalId,
  Value<String> hash,
  Value<String?> snapshotJson,
  Value<DateTime> setAt,
});

class $$VersionHashesTableFilterComposer
    extends Composer<_$AppDatabase, $VersionHashesTable> {
  $$VersionHashesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get table => $composableBuilder(
      column: $table.table, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get recordLocalId => $composableBuilder(
      column: $table.recordLocalId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get hash => $composableBuilder(
      column: $table.hash, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get snapshotJson => $composableBuilder(
      column: $table.snapshotJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get setAt => $composableBuilder(
      column: $table.setAt, builder: (column) => ColumnFilters(column));
}

class $$VersionHashesTableOrderingComposer
    extends Composer<_$AppDatabase, $VersionHashesTable> {
  $$VersionHashesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get table => $composableBuilder(
      column: $table.table, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get recordLocalId => $composableBuilder(
      column: $table.recordLocalId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get hash => $composableBuilder(
      column: $table.hash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get snapshotJson => $composableBuilder(
      column: $table.snapshotJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get setAt => $composableBuilder(
      column: $table.setAt, builder: (column) => ColumnOrderings(column));
}

class $$VersionHashesTableAnnotationComposer
    extends Composer<_$AppDatabase, $VersionHashesTable> {
  $$VersionHashesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get table =>
      $composableBuilder(column: $table.table, builder: (column) => column);

  GeneratedColumn<int> get recordLocalId => $composableBuilder(
      column: $table.recordLocalId, builder: (column) => column);

  GeneratedColumn<String> get hash =>
      $composableBuilder(column: $table.hash, builder: (column) => column);

  GeneratedColumn<String> get snapshotJson => $composableBuilder(
      column: $table.snapshotJson, builder: (column) => column);

  GeneratedColumn<DateTime> get setAt =>
      $composableBuilder(column: $table.setAt, builder: (column) => column);
}

class $$VersionHashesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $VersionHashesTable,
    VersionHashe,
    $$VersionHashesTableFilterComposer,
    $$VersionHashesTableOrderingComposer,
    $$VersionHashesTableAnnotationComposer,
    $$VersionHashesTableCreateCompanionBuilder,
    $$VersionHashesTableUpdateCompanionBuilder,
    (
      VersionHashe,
      BaseReferences<_$AppDatabase, $VersionHashesTable, VersionHashe>
    ),
    VersionHashe,
    PrefetchHooks Function()> {
  $$VersionHashesTableTableManager(_$AppDatabase db, $VersionHashesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VersionHashesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VersionHashesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VersionHashesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> table = const Value.absent(),
            Value<int> recordLocalId = const Value.absent(),
            Value<String> hash = const Value.absent(),
            Value<String?> snapshotJson = const Value.absent(),
            Value<DateTime> setAt = const Value.absent(),
          }) =>
              VersionHashesCompanion(
            id: id,
            table: table,
            recordLocalId: recordLocalId,
            hash: hash,
            snapshotJson: snapshotJson,
            setAt: setAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String table,
            required int recordLocalId,
            required String hash,
            Value<String?> snapshotJson = const Value.absent(),
            required DateTime setAt,
          }) =>
              VersionHashesCompanion.insert(
            id: id,
            table: table,
            recordLocalId: recordLocalId,
            hash: hash,
            snapshotJson: snapshotJson,
            setAt: setAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$VersionHashesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $VersionHashesTable,
    VersionHashe,
    $$VersionHashesTableFilterComposer,
    $$VersionHashesTableOrderingComposer,
    $$VersionHashesTableAnnotationComposer,
    $$VersionHashesTableCreateCompanionBuilder,
    $$VersionHashesTableUpdateCompanionBuilder,
    (
      VersionHashe,
      BaseReferences<_$AppDatabase, $VersionHashesTable, VersionHashe>
    ),
    VersionHashe,
    PrefetchHooks Function()>;
typedef $$ConflictsTableCreateCompanionBuilder = ConflictsCompanion Function({
  Value<int> id,
  required String recordType,
  required int recordLocalId,
  required String conflictingFields,
  Value<String?> localValue,
  Value<String?> remoteValue,
  Value<String> resolution,
  Value<bool> notified,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$ConflictsTableUpdateCompanionBuilder = ConflictsCompanion Function({
  Value<int> id,
  Value<String> recordType,
  Value<int> recordLocalId,
  Value<String> conflictingFields,
  Value<String?> localValue,
  Value<String?> remoteValue,
  Value<String> resolution,
  Value<bool> notified,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

class $$ConflictsTableFilterComposer
    extends Composer<_$AppDatabase, $ConflictsTable> {
  $$ConflictsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recordType => $composableBuilder(
      column: $table.recordType, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get recordLocalId => $composableBuilder(
      column: $table.recordLocalId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get conflictingFields => $composableBuilder(
      column: $table.conflictingFields,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get localValue => $composableBuilder(
      column: $table.localValue, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get remoteValue => $composableBuilder(
      column: $table.remoteValue, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get resolution => $composableBuilder(
      column: $table.resolution, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get notified => $composableBuilder(
      column: $table.notified, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$ConflictsTableOrderingComposer
    extends Composer<_$AppDatabase, $ConflictsTable> {
  $$ConflictsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recordType => $composableBuilder(
      column: $table.recordType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get recordLocalId => $composableBuilder(
      column: $table.recordLocalId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get conflictingFields => $composableBuilder(
      column: $table.conflictingFields,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get localValue => $composableBuilder(
      column: $table.localValue, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get remoteValue => $composableBuilder(
      column: $table.remoteValue, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get resolution => $composableBuilder(
      column: $table.resolution, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get notified => $composableBuilder(
      column: $table.notified, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$ConflictsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConflictsTable> {
  $$ConflictsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get recordType => $composableBuilder(
      column: $table.recordType, builder: (column) => column);

  GeneratedColumn<int> get recordLocalId => $composableBuilder(
      column: $table.recordLocalId, builder: (column) => column);

  GeneratedColumn<String> get conflictingFields => $composableBuilder(
      column: $table.conflictingFields, builder: (column) => column);

  GeneratedColumn<String> get localValue => $composableBuilder(
      column: $table.localValue, builder: (column) => column);

  GeneratedColumn<String> get remoteValue => $composableBuilder(
      column: $table.remoteValue, builder: (column) => column);

  GeneratedColumn<String> get resolution => $composableBuilder(
      column: $table.resolution, builder: (column) => column);

  GeneratedColumn<bool> get notified =>
      $composableBuilder(column: $table.notified, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ConflictsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ConflictsTable,
    Conflict,
    $$ConflictsTableFilterComposer,
    $$ConflictsTableOrderingComposer,
    $$ConflictsTableAnnotationComposer,
    $$ConflictsTableCreateCompanionBuilder,
    $$ConflictsTableUpdateCompanionBuilder,
    (Conflict, BaseReferences<_$AppDatabase, $ConflictsTable, Conflict>),
    Conflict,
    PrefetchHooks Function()> {
  $$ConflictsTableTableManager(_$AppDatabase db, $ConflictsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConflictsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConflictsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConflictsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> recordType = const Value.absent(),
            Value<int> recordLocalId = const Value.absent(),
            Value<String> conflictingFields = const Value.absent(),
            Value<String?> localValue = const Value.absent(),
            Value<String?> remoteValue = const Value.absent(),
            Value<String> resolution = const Value.absent(),
            Value<bool> notified = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              ConflictsCompanion(
            id: id,
            recordType: recordType,
            recordLocalId: recordLocalId,
            conflictingFields: conflictingFields,
            localValue: localValue,
            remoteValue: remoteValue,
            resolution: resolution,
            notified: notified,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String recordType,
            required int recordLocalId,
            required String conflictingFields,
            Value<String?> localValue = const Value.absent(),
            Value<String?> remoteValue = const Value.absent(),
            Value<String> resolution = const Value.absent(),
            Value<bool> notified = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              ConflictsCompanion.insert(
            id: id,
            recordType: recordType,
            recordLocalId: recordLocalId,
            conflictingFields: conflictingFields,
            localValue: localValue,
            remoteValue: remoteValue,
            resolution: resolution,
            notified: notified,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ConflictsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ConflictsTable,
    Conflict,
    $$ConflictsTableFilterComposer,
    $$ConflictsTableOrderingComposer,
    $$ConflictsTableAnnotationComposer,
    $$ConflictsTableCreateCompanionBuilder,
    $$ConflictsTableUpdateCompanionBuilder,
    (Conflict, BaseReferences<_$AppDatabase, $ConflictsTable, Conflict>),
    Conflict,
    PrefetchHooks Function()>;
typedef $$PaymentEventsTableCreateCompanionBuilder = PaymentEventsCompanion
    Function({
  Value<int> id,
  required String transactionReference,
  Value<bool> confirmedByWebhook,
  required int amount,
  required String plan,
  Value<DateTime> createdAt,
  Value<DateTime?> confirmationDate,
});
typedef $$PaymentEventsTableUpdateCompanionBuilder = PaymentEventsCompanion
    Function({
  Value<int> id,
  Value<String> transactionReference,
  Value<bool> confirmedByWebhook,
  Value<int> amount,
  Value<String> plan,
  Value<DateTime> createdAt,
  Value<DateTime?> confirmationDate,
});

class $$PaymentEventsTableFilterComposer
    extends Composer<_$AppDatabase, $PaymentEventsTable> {
  $$PaymentEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get transactionReference => $composableBuilder(
      column: $table.transactionReference,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get confirmedByWebhook => $composableBuilder(
      column: $table.confirmedByWebhook,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get plan => $composableBuilder(
      column: $table.plan, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get confirmationDate => $composableBuilder(
      column: $table.confirmationDate,
      builder: (column) => ColumnFilters(column));
}

class $$PaymentEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $PaymentEventsTable> {
  $$PaymentEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get transactionReference => $composableBuilder(
      column: $table.transactionReference,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get confirmedByWebhook => $composableBuilder(
      column: $table.confirmedByWebhook,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get plan => $composableBuilder(
      column: $table.plan, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get confirmationDate => $composableBuilder(
      column: $table.confirmationDate,
      builder: (column) => ColumnOrderings(column));
}

class $$PaymentEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PaymentEventsTable> {
  $$PaymentEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get transactionReference => $composableBuilder(
      column: $table.transactionReference, builder: (column) => column);

  GeneratedColumn<bool> get confirmedByWebhook => $composableBuilder(
      column: $table.confirmedByWebhook, builder: (column) => column);

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get plan =>
      $composableBuilder(column: $table.plan, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get confirmationDate => $composableBuilder(
      column: $table.confirmationDate, builder: (column) => column);
}

class $$PaymentEventsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PaymentEventsTable,
    PaymentEvent,
    $$PaymentEventsTableFilterComposer,
    $$PaymentEventsTableOrderingComposer,
    $$PaymentEventsTableAnnotationComposer,
    $$PaymentEventsTableCreateCompanionBuilder,
    $$PaymentEventsTableUpdateCompanionBuilder,
    (
      PaymentEvent,
      BaseReferences<_$AppDatabase, $PaymentEventsTable, PaymentEvent>
    ),
    PaymentEvent,
    PrefetchHooks Function()> {
  $$PaymentEventsTableTableManager(_$AppDatabase db, $PaymentEventsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PaymentEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PaymentEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PaymentEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> transactionReference = const Value.absent(),
            Value<bool> confirmedByWebhook = const Value.absent(),
            Value<int> amount = const Value.absent(),
            Value<String> plan = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> confirmationDate = const Value.absent(),
          }) =>
              PaymentEventsCompanion(
            id: id,
            transactionReference: transactionReference,
            confirmedByWebhook: confirmedByWebhook,
            amount: amount,
            plan: plan,
            createdAt: createdAt,
            confirmationDate: confirmationDate,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String transactionReference,
            Value<bool> confirmedByWebhook = const Value.absent(),
            required int amount,
            required String plan,
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> confirmationDate = const Value.absent(),
          }) =>
              PaymentEventsCompanion.insert(
            id: id,
            transactionReference: transactionReference,
            confirmedByWebhook: confirmedByWebhook,
            amount: amount,
            plan: plan,
            createdAt: createdAt,
            confirmationDate: confirmationDate,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PaymentEventsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PaymentEventsTable,
    PaymentEvent,
    $$PaymentEventsTableFilterComposer,
    $$PaymentEventsTableOrderingComposer,
    $$PaymentEventsTableAnnotationComposer,
    $$PaymentEventsTableCreateCompanionBuilder,
    $$PaymentEventsTableUpdateCompanionBuilder,
    (
      PaymentEvent,
      BaseReferences<_$AppDatabase, $PaymentEventsTable, PaymentEvent>
    ),
    PaymentEvent,
    PrefetchHooks Function()>;
typedef $$RecoveryCodesTableCreateCompanionBuilder = RecoveryCodesCompanion
    Function({
  Value<int> id,
});
typedef $$RecoveryCodesTableUpdateCompanionBuilder = RecoveryCodesCompanion
    Function({
  Value<int> id,
});

class $$RecoveryCodesTableFilterComposer
    extends Composer<_$AppDatabase, $RecoveryCodesTable> {
  $$RecoveryCodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));
}

class $$RecoveryCodesTableOrderingComposer
    extends Composer<_$AppDatabase, $RecoveryCodesTable> {
  $$RecoveryCodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));
}

class $$RecoveryCodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecoveryCodesTable> {
  $$RecoveryCodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);
}

class $$RecoveryCodesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RecoveryCodesTable,
    RecoveryCode,
    $$RecoveryCodesTableFilterComposer,
    $$RecoveryCodesTableOrderingComposer,
    $$RecoveryCodesTableAnnotationComposer,
    $$RecoveryCodesTableCreateCompanionBuilder,
    $$RecoveryCodesTableUpdateCompanionBuilder,
    (
      RecoveryCode,
      BaseReferences<_$AppDatabase, $RecoveryCodesTable, RecoveryCode>
    ),
    RecoveryCode,
    PrefetchHooks Function()> {
  $$RecoveryCodesTableTableManager(_$AppDatabase db, $RecoveryCodesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecoveryCodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecoveryCodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecoveryCodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
          }) =>
              RecoveryCodesCompanion(
            id: id,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
          }) =>
              RecoveryCodesCompanion.insert(
            id: id,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$RecoveryCodesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $RecoveryCodesTable,
    RecoveryCode,
    $$RecoveryCodesTableFilterComposer,
    $$RecoveryCodesTableOrderingComposer,
    $$RecoveryCodesTableAnnotationComposer,
    $$RecoveryCodesTableCreateCompanionBuilder,
    $$RecoveryCodesTableUpdateCompanionBuilder,
    (
      RecoveryCode,
      BaseReferences<_$AppDatabase, $RecoveryCodesTable, RecoveryCode>
    ),
    RecoveryCode,
    PrefetchHooks Function()>;
typedef $$PendingRecoveryRequestsTableCreateCompanionBuilder
    = PendingRecoveryRequestsCompanion Function({
  Value<int> id,
  required String email,
  required DateTime attemptedAt,
});
typedef $$PendingRecoveryRequestsTableUpdateCompanionBuilder
    = PendingRecoveryRequestsCompanion Function({
  Value<int> id,
  Value<String> email,
  Value<DateTime> attemptedAt,
});

class $$PendingRecoveryRequestsTableFilterComposer
    extends Composer<_$AppDatabase, $PendingRecoveryRequestsTable> {
  $$PendingRecoveryRequestsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get email => $composableBuilder(
      column: $table.email, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get attemptedAt => $composableBuilder(
      column: $table.attemptedAt, builder: (column) => ColumnFilters(column));
}

class $$PendingRecoveryRequestsTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingRecoveryRequestsTable> {
  $$PendingRecoveryRequestsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get email => $composableBuilder(
      column: $table.email, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get attemptedAt => $composableBuilder(
      column: $table.attemptedAt, builder: (column) => ColumnOrderings(column));
}

class $$PendingRecoveryRequestsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingRecoveryRequestsTable> {
  $$PendingRecoveryRequestsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<DateTime> get attemptedAt => $composableBuilder(
      column: $table.attemptedAt, builder: (column) => column);
}

class $$PendingRecoveryRequestsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PendingRecoveryRequestsTable,
    PendingRecoveryRequest,
    $$PendingRecoveryRequestsTableFilterComposer,
    $$PendingRecoveryRequestsTableOrderingComposer,
    $$PendingRecoveryRequestsTableAnnotationComposer,
    $$PendingRecoveryRequestsTableCreateCompanionBuilder,
    $$PendingRecoveryRequestsTableUpdateCompanionBuilder,
    (
      PendingRecoveryRequest,
      BaseReferences<_$AppDatabase, $PendingRecoveryRequestsTable,
          PendingRecoveryRequest>
    ),
    PendingRecoveryRequest,
    PrefetchHooks Function()> {
  $$PendingRecoveryRequestsTableTableManager(
      _$AppDatabase db, $PendingRecoveryRequestsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingRecoveryRequestsTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingRecoveryRequestsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingRecoveryRequestsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> email = const Value.absent(),
            Value<DateTime> attemptedAt = const Value.absent(),
          }) =>
              PendingRecoveryRequestsCompanion(
            id: id,
            email: email,
            attemptedAt: attemptedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String email,
            required DateTime attemptedAt,
          }) =>
              PendingRecoveryRequestsCompanion.insert(
            id: id,
            email: email,
            attemptedAt: attemptedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PendingRecoveryRequestsTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $PendingRecoveryRequestsTable,
        PendingRecoveryRequest,
        $$PendingRecoveryRequestsTableFilterComposer,
        $$PendingRecoveryRequestsTableOrderingComposer,
        $$PendingRecoveryRequestsTableAnnotationComposer,
        $$PendingRecoveryRequestsTableCreateCompanionBuilder,
        $$PendingRecoveryRequestsTableUpdateCompanionBuilder,
        (
          PendingRecoveryRequest,
          BaseReferences<_$AppDatabase, $PendingRecoveryRequestsTable,
              PendingRecoveryRequest>
        ),
        PendingRecoveryRequest,
        PrefetchHooks Function()>;
typedef $$TeacherDevicesTableCreateCompanionBuilder = TeacherDevicesCompanion
    Function({
  Value<int> id,
});
typedef $$TeacherDevicesTableUpdateCompanionBuilder = TeacherDevicesCompanion
    Function({
  Value<int> id,
});

class $$TeacherDevicesTableFilterComposer
    extends Composer<_$AppDatabase, $TeacherDevicesTable> {
  $$TeacherDevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));
}

class $$TeacherDevicesTableOrderingComposer
    extends Composer<_$AppDatabase, $TeacherDevicesTable> {
  $$TeacherDevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));
}

class $$TeacherDevicesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TeacherDevicesTable> {
  $$TeacherDevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);
}

class $$TeacherDevicesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TeacherDevicesTable,
    TeacherDevice,
    $$TeacherDevicesTableFilterComposer,
    $$TeacherDevicesTableOrderingComposer,
    $$TeacherDevicesTableAnnotationComposer,
    $$TeacherDevicesTableCreateCompanionBuilder,
    $$TeacherDevicesTableUpdateCompanionBuilder,
    (
      TeacherDevice,
      BaseReferences<_$AppDatabase, $TeacherDevicesTable, TeacherDevice>
    ),
    TeacherDevice,
    PrefetchHooks Function()> {
  $$TeacherDevicesTableTableManager(
      _$AppDatabase db, $TeacherDevicesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TeacherDevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TeacherDevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TeacherDevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
          }) =>
              TeacherDevicesCompanion(
            id: id,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
          }) =>
              TeacherDevicesCompanion.insert(
            id: id,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TeacherDevicesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TeacherDevicesTable,
    TeacherDevice,
    $$TeacherDevicesTableFilterComposer,
    $$TeacherDevicesTableOrderingComposer,
    $$TeacherDevicesTableAnnotationComposer,
    $$TeacherDevicesTableCreateCompanionBuilder,
    $$TeacherDevicesTableUpdateCompanionBuilder,
    (
      TeacherDevice,
      BaseReferences<_$AppDatabase, $TeacherDevicesTable, TeacherDevice>
    ),
    TeacherDevice,
    PrefetchHooks Function()>;
typedef $$SchemeGenerationQueueTableCreateCompanionBuilder
    = SchemeGenerationQueueCompanion Function({
  Value<int> id,
});
typedef $$SchemeGenerationQueueTableUpdateCompanionBuilder
    = SchemeGenerationQueueCompanion Function({
  Value<int> id,
});

class $$SchemeGenerationQueueTableFilterComposer
    extends Composer<_$AppDatabase, $SchemeGenerationQueueTable> {
  $$SchemeGenerationQueueTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));
}

class $$SchemeGenerationQueueTableOrderingComposer
    extends Composer<_$AppDatabase, $SchemeGenerationQueueTable> {
  $$SchemeGenerationQueueTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));
}

class $$SchemeGenerationQueueTableAnnotationComposer
    extends Composer<_$AppDatabase, $SchemeGenerationQueueTable> {
  $$SchemeGenerationQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);
}

class $$SchemeGenerationQueueTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SchemeGenerationQueueTable,
    SchemeGenerationQueueData,
    $$SchemeGenerationQueueTableFilterComposer,
    $$SchemeGenerationQueueTableOrderingComposer,
    $$SchemeGenerationQueueTableAnnotationComposer,
    $$SchemeGenerationQueueTableCreateCompanionBuilder,
    $$SchemeGenerationQueueTableUpdateCompanionBuilder,
    (
      SchemeGenerationQueueData,
      BaseReferences<_$AppDatabase, $SchemeGenerationQueueTable,
          SchemeGenerationQueueData>
    ),
    SchemeGenerationQueueData,
    PrefetchHooks Function()> {
  $$SchemeGenerationQueueTableTableManager(
      _$AppDatabase db, $SchemeGenerationQueueTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SchemeGenerationQueueTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$SchemeGenerationQueueTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SchemeGenerationQueueTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
          }) =>
              SchemeGenerationQueueCompanion(
            id: id,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
          }) =>
              SchemeGenerationQueueCompanion.insert(
            id: id,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SchemeGenerationQueueTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $SchemeGenerationQueueTable,
        SchemeGenerationQueueData,
        $$SchemeGenerationQueueTableFilterComposer,
        $$SchemeGenerationQueueTableOrderingComposer,
        $$SchemeGenerationQueueTableAnnotationComposer,
        $$SchemeGenerationQueueTableCreateCompanionBuilder,
        $$SchemeGenerationQueueTableUpdateCompanionBuilder,
        (
          SchemeGenerationQueueData,
          BaseReferences<_$AppDatabase, $SchemeGenerationQueueTable,
              SchemeGenerationQueueData>
        ),
        SchemeGenerationQueueData,
        PrefetchHooks Function()>;
typedef $$PdfCacheTableCreateCompanionBuilder = PdfCacheCompanion Function({
  required String cacheKey,
  required Uint8List pdfData,
  required DateTime cachedAt,
  Value<int> rowid,
});
typedef $$PdfCacheTableUpdateCompanionBuilder = PdfCacheCompanion Function({
  Value<String> cacheKey,
  Value<Uint8List> pdfData,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});

class $$PdfCacheTableFilterComposer
    extends Composer<_$AppDatabase, $PdfCacheTable> {
  $$PdfCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get cacheKey => $composableBuilder(
      column: $table.cacheKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get pdfData => $composableBuilder(
      column: $table.pdfData, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$PdfCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $PdfCacheTable> {
  $$PdfCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get cacheKey => $composableBuilder(
      column: $table.cacheKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get pdfData => $composableBuilder(
      column: $table.pdfData, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$PdfCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $PdfCacheTable> {
  $$PdfCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<Uint8List> get pdfData =>
      $composableBuilder(column: $table.pdfData, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$PdfCacheTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PdfCacheTable,
    PdfCacheData,
    $$PdfCacheTableFilterComposer,
    $$PdfCacheTableOrderingComposer,
    $$PdfCacheTableAnnotationComposer,
    $$PdfCacheTableCreateCompanionBuilder,
    $$PdfCacheTableUpdateCompanionBuilder,
    (PdfCacheData, BaseReferences<_$AppDatabase, $PdfCacheTable, PdfCacheData>),
    PdfCacheData,
    PrefetchHooks Function()> {
  $$PdfCacheTableTableManager(_$AppDatabase db, $PdfCacheTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PdfCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PdfCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PdfCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> cacheKey = const Value.absent(),
            Value<Uint8List> pdfData = const Value.absent(),
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PdfCacheCompanion(
            cacheKey: cacheKey,
            pdfData: pdfData,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String cacheKey,
            required Uint8List pdfData,
            required DateTime cachedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              PdfCacheCompanion.insert(
            cacheKey: cacheKey,
            pdfData: pdfData,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PdfCacheTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PdfCacheTable,
    PdfCacheData,
    $$PdfCacheTableFilterComposer,
    $$PdfCacheTableOrderingComposer,
    $$PdfCacheTableAnnotationComposer,
    $$PdfCacheTableCreateCompanionBuilder,
    $$PdfCacheTableUpdateCompanionBuilder,
    (PdfCacheData, BaseReferences<_$AppDatabase, $PdfCacheTable, PdfCacheData>),
    PdfCacheData,
    PrefetchHooks Function()>;
typedef $$TeacherSubjectsTableCreateCompanionBuilder = TeacherSubjectsCompanion
    Function({
  Value<int> id,
  required int teacherLocalId,
  required int subjectId,
});
typedef $$TeacherSubjectsTableUpdateCompanionBuilder = TeacherSubjectsCompanion
    Function({
  Value<int> id,
  Value<int> teacherLocalId,
  Value<int> subjectId,
});

final class $$TeacherSubjectsTableReferences extends BaseReferences<
    _$AppDatabase, $TeacherSubjectsTable, TeacherSubject> {
  $$TeacherSubjectsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $TeachersTable _teacherLocalIdTable(_$AppDatabase db) =>
      db.teachers.createAlias($_aliasNameGenerator(
          db.teacherSubjects.teacherLocalId, db.teachers.localId));

  $$TeachersTableProcessedTableManager get teacherLocalId {
    final $_column = $_itemColumn<int>('teacher_local_id')!;

    final manager = $$TeachersTableTableManager($_db, $_db.teachers)
        .filter((f) => f.localId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_teacherLocalIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $SubjectsTable _subjectIdTable(_$AppDatabase db) =>
      db.subjects.createAlias(
          $_aliasNameGenerator(db.teacherSubjects.subjectId, db.subjects.id));

  $$SubjectsTableProcessedTableManager get subjectId {
    final $_column = $_itemColumn<int>('subject_id')!;

    final manager = $$SubjectsTableTableManager($_db, $_db.subjects)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_subjectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$TeacherSubjectsTableFilterComposer
    extends Composer<_$AppDatabase, $TeacherSubjectsTable> {
  $$TeacherSubjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  $$TeachersTableFilterComposer get teacherLocalId {
    final $$TeachersTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.teacherLocalId,
        referencedTable: $db.teachers,
        getReferencedColumn: (t) => t.localId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TeachersTableFilterComposer(
              $db: $db,
              $table: $db.teachers,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$SubjectsTableFilterComposer get subjectId {
    final $$SubjectsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.subjectId,
        referencedTable: $db.subjects,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SubjectsTableFilterComposer(
              $db: $db,
              $table: $db.subjects,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TeacherSubjectsTableOrderingComposer
    extends Composer<_$AppDatabase, $TeacherSubjectsTable> {
  $$TeacherSubjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  $$TeachersTableOrderingComposer get teacherLocalId {
    final $$TeachersTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.teacherLocalId,
        referencedTable: $db.teachers,
        getReferencedColumn: (t) => t.localId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TeachersTableOrderingComposer(
              $db: $db,
              $table: $db.teachers,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$SubjectsTableOrderingComposer get subjectId {
    final $$SubjectsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.subjectId,
        referencedTable: $db.subjects,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SubjectsTableOrderingComposer(
              $db: $db,
              $table: $db.subjects,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TeacherSubjectsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TeacherSubjectsTable> {
  $$TeacherSubjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  $$TeachersTableAnnotationComposer get teacherLocalId {
    final $$TeachersTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.teacherLocalId,
        referencedTable: $db.teachers,
        getReferencedColumn: (t) => t.localId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TeachersTableAnnotationComposer(
              $db: $db,
              $table: $db.teachers,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$SubjectsTableAnnotationComposer get subjectId {
    final $$SubjectsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.subjectId,
        referencedTable: $db.subjects,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SubjectsTableAnnotationComposer(
              $db: $db,
              $table: $db.subjects,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TeacherSubjectsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TeacherSubjectsTable,
    TeacherSubject,
    $$TeacherSubjectsTableFilterComposer,
    $$TeacherSubjectsTableOrderingComposer,
    $$TeacherSubjectsTableAnnotationComposer,
    $$TeacherSubjectsTableCreateCompanionBuilder,
    $$TeacherSubjectsTableUpdateCompanionBuilder,
    (TeacherSubject, $$TeacherSubjectsTableReferences),
    TeacherSubject,
    PrefetchHooks Function({bool teacherLocalId, bool subjectId})> {
  $$TeacherSubjectsTableTableManager(
      _$AppDatabase db, $TeacherSubjectsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TeacherSubjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TeacherSubjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TeacherSubjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> teacherLocalId = const Value.absent(),
            Value<int> subjectId = const Value.absent(),
          }) =>
              TeacherSubjectsCompanion(
            id: id,
            teacherLocalId: teacherLocalId,
            subjectId: subjectId,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int teacherLocalId,
            required int subjectId,
          }) =>
              TeacherSubjectsCompanion.insert(
            id: id,
            teacherLocalId: teacherLocalId,
            subjectId: subjectId,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$TeacherSubjectsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({teacherLocalId = false, subjectId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (teacherLocalId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.teacherLocalId,
                    referencedTable: $$TeacherSubjectsTableReferences
                        ._teacherLocalIdTable(db),
                    referencedColumn: $$TeacherSubjectsTableReferences
                        ._teacherLocalIdTable(db)
                        .localId,
                  ) as T;
                }
                if (subjectId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.subjectId,
                    referencedTable:
                        $$TeacherSubjectsTableReferences._subjectIdTable(db),
                    referencedColumn:
                        $$TeacherSubjectsTableReferences._subjectIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$TeacherSubjectsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TeacherSubjectsTable,
    TeacherSubject,
    $$TeacherSubjectsTableFilterComposer,
    $$TeacherSubjectsTableOrderingComposer,
    $$TeacherSubjectsTableAnnotationComposer,
    $$TeacherSubjectsTableCreateCompanionBuilder,
    $$TeacherSubjectsTableUpdateCompanionBuilder,
    (TeacherSubject, $$TeacherSubjectsTableReferences),
    TeacherSubject,
    PrefetchHooks Function({bool teacherLocalId, bool subjectId})>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SchoolsTableTableManager get schools =>
      $$SchoolsTableTableManager(_db, _db.schools);
  $$TeachersTableTableManager get teachers =>
      $$TeachersTableTableManager(_db, _db.teachers);
  $$SubjectsTableTableManager get subjects =>
      $$SubjectsTableTableManager(_db, _db.subjects);
  $$LessonsTableTableManager get lessons =>
      $$LessonsTableTableManager(_db, _db.lessons);
  $$SchemeOfWorkTableTableManager get schemeOfWork =>
      $$SchemeOfWorkTableTableManager(_db, _db.schemeOfWork);
  $$ExamsTableTableManager get exams =>
      $$ExamsTableTableManager(_db, _db.exams);
  $$ProgressLogsTableTableManager get progressLogs =>
      $$ProgressLogsTableTableManager(_db, _db.progressLogs);
  $$VaultItemsTableTableManager get vaultItems =>
      $$VaultItemsTableTableManager(_db, _db.vaultItems);
  $$SecurityConfigTableTableManager get securityConfig =>
      $$SecurityConfigTableTableManager(_db, _db.securityConfig);
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db, _db.syncQueue);
  $$SyncQueueSnapshotTableTableManager get syncQueueSnapshot =>
      $$SyncQueueSnapshotTableTableManager(_db, _db.syncQueueSnapshot);
  $$VersionHashesTableTableManager get versionHashes =>
      $$VersionHashesTableTableManager(_db, _db.versionHashes);
  $$ConflictsTableTableManager get conflicts =>
      $$ConflictsTableTableManager(_db, _db.conflicts);
  $$PaymentEventsTableTableManager get paymentEvents =>
      $$PaymentEventsTableTableManager(_db, _db.paymentEvents);
  $$RecoveryCodesTableTableManager get recoveryCodes =>
      $$RecoveryCodesTableTableManager(_db, _db.recoveryCodes);
  $$PendingRecoveryRequestsTableTableManager get pendingRecoveryRequests =>
      $$PendingRecoveryRequestsTableTableManager(
          _db, _db.pendingRecoveryRequests);
  $$TeacherDevicesTableTableManager get teacherDevices =>
      $$TeacherDevicesTableTableManager(_db, _db.teacherDevices);
  $$SchemeGenerationQueueTableTableManager get schemeGenerationQueue =>
      $$SchemeGenerationQueueTableTableManager(_db, _db.schemeGenerationQueue);
  $$PdfCacheTableTableManager get pdfCache =>
      $$PdfCacheTableTableManager(_db, _db.pdfCache);
  $$TeacherSubjectsTableTableManager get teacherSubjects =>
      $$TeacherSubjectsTableTableManager(_db, _db.teacherSubjects);
}
