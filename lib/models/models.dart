// lib/models/models.dart
import 'package:flutter/material.dart';

/// 使用者資料模型（可選，根據實際需求使用）
class User {
  final String staffId;
  final String name;
  final String nickname;
  final String jobTitle;
  final String group;
  final String permissionCode;

  User({
    required this.staffId,
    required this.name,
    required this.nickname,
    required this.jobTitle,
    required this.group,
    required this.permissionCode,
  });

  Map<String, dynamic> toMap() {
    return {
      'staffId': staffId,
      'name': name,
      'nickname': nickname,
      'jobTitle': jobTitle,
      'group': group,
      'permissionCode': permissionCode,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      staffId: map['staffId'] ?? '',
      name: map['name'] ?? '',
      nickname: map['nickname'] ?? '',
      jobTitle: map['jobTitle'] ?? '',
      group: map['group'] ?? 'A',
      permissionCode: map['permissionCode'] ?? '',
    );
  }
}

/// 請假記錄資料模型（可選，根據實際需求使用）
class LeaveRecord {
  final String id;
  final String dateKey;
  final DateTime date;
  final String shift;
  final List<String> names;
  final List<String> reasons;
  final List<String> staffIds;
  final String status; // 'pending', 'approved', 'rejected', 'partial', 'cancelled'
  final List<String> statuses; // 每人狀態
  final DateTime updatedAt;

  LeaveRecord({
    required this.id,
    required this.dateKey,
    required this.date,
    required this.shift,
    required this.names,
    required this.reasons,
    required this.staffIds,
    required this.status,
    required this.statuses,
    required this.updatedAt,
  });

  factory LeaveRecord.fromFirestore(Map<String, dynamic> data, String docId) {
    return LeaveRecord(
      id: docId,
      dateKey: data['dateKey'] ?? docId,
      date: (data['date'] as dynamic).toDate(),
      shift: data['shift'] ?? '',
      names: List<String>.from(data['names'] ?? []),
      reasons: List<String>.from(data['reasons'] ?? []),
      staffIds: List<String>.from(data['staffIds'] ?? []),
      status: data['status'] ?? 'pending',
      statuses: List<String>.from(data['statuses'] ?? []),
      updatedAt: (data['updatedAt'] as dynamic)?.toDate() ?? DateTime.now(),
    );
  }
}