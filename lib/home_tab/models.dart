import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum PlaceStatus { free, preliminary, booked }

extension PlaceStatusExtension on PlaceStatus {
  String get displayName {
    switch (this) {
      case PlaceStatus.free:
        return 'Свободно';
      case PlaceStatus.preliminary:
        return 'Предбронь';
      case PlaceStatus.booked:
        return 'Забронировано';
    }
  }

  Color get color {
    switch (this) {
      case PlaceStatus.free:
        return Colors.orange;
      case PlaceStatus.preliminary:
        return Colors.blue;
      case PlaceStatus.booked:
        return Colors.green;
    }
  }
}

class ExhibitionPlace {
  final String id;
  final String number;
  final List<String> preferredCategoryIds; // вместо preferredCategories как строка
  final double size;
  final PlaceStatus status;
  final double price;
  final String? assignedUserId;

  ExhibitionPlace({
    required this.id,
    required this.number,
    required this.preferredCategoryIds,
    required this.size,
    required this.status,
    required this.price,
    this.assignedUserId,
  });

  factory ExhibitionPlace.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    PlaceStatus status;
    if (data['status'] is String) {
      status = PlaceStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => PlaceStatus.free,
      );
    } else if (data['isBooked'] == true) {
      status = PlaceStatus.booked;
    } else {
      status = PlaceStatus.free;
    }

    double size = 0.0;
    if (data['size'] is double) {
      size = data['size'];
    } else if (data['size'] is String) {
      size = double.tryParse(data['size']) ?? 0.0;
    } else if (data['size'] is num) {
      size = (data['size'] as num).toDouble();
    }

    double price = 0.0;
    if (data['price'] is double) {
      price = data['price'];
    } else if (data['price'] is String) {
      price = double.tryParse(data['price']) ?? 0.0;
    } else if (data['price'] is num) {
      price = (data['price'] as num).toDouble();
    }

    List<String> preferredCategoryIds = [];
    final raw = data['preferredCategoryIds'];
    if (raw is List) {
      preferredCategoryIds =
          raw.map((e) => e.toString()).toList();
    }

    return ExhibitionPlace(
      id: doc.id,
      number: data['number'] ?? '',
      preferredCategoryIds: preferredCategoryIds,
      size: size,
      status: status,
      price: price,
      assignedUserId: data['assignedUserId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'number': number,
      'preferredCategoryIds': preferredCategoryIds,
      'size': size,
      'status': status.name,
      'price': price,
      'assignedUserId': assignedUserId,
    };
  }
}

class UserCategory {
  final String id;
  final String type;
  final String categoryId; // вместо priceCategory
  final double preferredSize;
  final String? comment;
  final String userId;
  String userName;

  UserCategory({
    required this.id,
    required this.type,
    required this.categoryId,
    required this.preferredSize,
    this.comment,
    required this.userId,
    this.userName = '',
  });
}

class CategoryEntity {
  final String id;
  final String name;
  final String priceCategoryName; // если нужно отображать старое имя
  final double size;
  final double price;

  CategoryEntity({
    required this.id,
    required this.name,
    this.priceCategoryName = '',
    required this.size,
    required this.price,
  });

  factory CategoryEntity.fromFirestore(String docId, DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CategoryEntity(
      id: docId,
      name: data['name'] ?? '',
      priceCategoryName: data['priceCategory'] ?? '',
      size: (data['size'] as num?)?.toDouble() ?? 0.0,
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class Exhibition {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final int capacity;
  final String? layoutImageUrl;
  final bool isActive;

  Exhibition({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.capacity,
    this.layoutImageUrl,
    required this.isActive,
  });

  factory Exhibition.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final start = (data['startDate'] as Timestamp).toDate();
    final end = (data['endDate'] as Timestamp).toDate();
    return Exhibition(
      id: doc.id,
      name: data['name'] ?? '',
      startDate: start,
      endDate: end,
      capacity: data['capacity'] ?? 0,
      layoutImageUrl: data['layoutImageUrl'],
      isActive: DateTime.now().isBefore(end) || DateTime.now().isAtSameMomentAs(end),
    );
  }
}