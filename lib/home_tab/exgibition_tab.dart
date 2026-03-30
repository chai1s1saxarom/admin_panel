import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';

// ---------- Модели данных ----------

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
  final List<String> preferredCategories;
  final double size; // размер места, выбранный при создании
  final PlaceStatus status;
  final double? price;
  final String? assignedUserId;

  ExhibitionPlace({
    required this.id,
    required this.number,
    required this.preferredCategories,
    required this.size,
    required this.status,
    this.price,
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

    return ExhibitionPlace(
      id: doc.id,
      number: data['number'] ?? '',
      preferredCategories: List<String>.from(data['preferredCategories'] ?? []),
      size: size,
      status: status,
      price: (data['price'] as num?)?.toDouble(),
      assignedUserId: data['assignedUserId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'number': number,
      'preferredCategories': preferredCategories,
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
  final String priceCategory;
  final double preferredSize;
  final String? comment;
  final String userId;

  UserCategory({
    required this.id,
    required this.type,
    required this.priceCategory,
    required this.preferredSize,
    this.comment,
    required this.userId,
  });

  factory UserCategory.fromFirestore(DocumentSnapshot doc, String userId) {
    final data = doc.data() as Map<String, dynamic>;
    double preferredSize = 0.0;
    if (data['size'] is double) {
      preferredSize = data['size'];
    } else if (data['size'] is String) {
      preferredSize = double.tryParse(data['size']) ?? 0.0;
    } else if (data['size'] is num) {
      preferredSize = (data['size'] as num).toDouble();
    }
    return UserCategory(
      id: doc.id,
      type: data['name'] ?? '',
      priceCategory: data['priceCategory'] ?? '',
      preferredSize: preferredSize,
      comment: data['comment'],
      userId: userId,
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

// ---------- Таб с выставками ----------
class ExhibitionsTab extends StatelessWidget {
  const ExhibitionsTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Выставки')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('exhibitions').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Ошибка: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final exhibitions = snapshot.data!.docs;

          return ListView.builder(
            itemCount: exhibitions.length,
            itemBuilder: (context, index) {
              final exDoc = exhibitions[index];
              final ex = Exhibition.fromFirestore(exDoc);

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(
                    ex.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text('📅 ${_formatDate(ex.startDate)} - ${_formatDate(ex.endDate)}'),
                      Text('📍 Количество мест: ${ex.capacity}'),
                      Text('💰 Статус: ${ex.isActive ? 'Активна' : 'Завершена'}'),
                    ],
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ExhibitionDetailScreen(
                          exhibitionId: ex.id,
                          exhibitionName: ex.name,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateExhibitionDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd.MM.yyyy').format(date);
  }

  void _showCreateExhibitionDialog(BuildContext context) {
    final nameController = TextEditingController();
    DateTime? startDate;
    DateTime? endDate;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Новая выставка'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Название'),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    title: Text(
                      startDate == null
                          ? 'Выберите дату начала'
                          : 'Начало: ${DateFormat('dd.MM.yyyy').format(startDate!)}',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => startDate = picked);
                      }
                    },
                  ),
                  ListTile(
                    title: Text(
                      endDate == null
                          ? 'Выберите дату окончания'
                          : 'Окончание: ${DateFormat('dd.MM.yyyy').format(endDate!)}',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: startDate ?? DateTime.now(),
                        firstDate: startDate ?? DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => endDate = picked);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isEmpty || startDate == null || endDate == null) return;
                    await FirebaseFirestore.instance.collection('exhibitions').add({
                      'name': nameController.text,
                      'startDate': Timestamp.fromDate(startDate!),
                      'endDate': Timestamp.fromDate(endDate!),
                      'capacity': 0,
                      'layoutImageUrl': null,
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Создать'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ---------- Экран деталей выставки ----------
class ExhibitionDetailScreen extends StatefulWidget {
  final String exhibitionId;
  final String exhibitionName;

  const ExhibitionDetailScreen({
    Key? key,
    required this.exhibitionId,
    required this.exhibitionName,
  }) : super(key: key);

  @override
  State<ExhibitionDetailScreen> createState() => _ExhibitionDetailScreenState();
}

class _ExhibitionDetailScreenState extends State<ExhibitionDetailScreen> {
  final List<UserCategory> _availableUsers = [];
  bool _isLoadingUsers = false;

  @override
  void initState() {
    super.initState();
    _loadAvailableUsers();
  }

  Future<void> _loadAvailableUsers() async {
    setState(() => _isLoadingUsers = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('categories')
          .get();

      _availableUsers.clear();
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final assignedUsers = List<String>.from(data['assignedUsers'] ?? []);
        for (var userId in assignedUsers) {
          _availableUsers.add(UserCategory(
            id: doc.id,
            type: data['name'] ?? '',
            priceCategory: data['priceCategory'] ?? '',
            preferredSize: (data['size'] as num?)?.toDouble() ?? 0.0,
            comment: null,
            userId: userId,
          ));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки категорий: $e')),
      );
    } finally {
      setState(() => _isLoadingUsers = false);
    }
  }

  // Получение всех категорий из Firestore
  Future<List<Map<String, dynamic>>> _getAllCategories() async {
    final snapshot = await FirebaseFirestore.instance.collection('categories').get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'name': data['name'] ?? '',
        'priceCategory': data['priceCategory'] ?? '',
        'size': (data['size'] as num?)?.toDouble() ?? 0.0,
        'price': (data['price'] as num?)?.toDouble(),
      };
    }).toList();
  }

  List<UserCategory> _findSuitableUsers(ExhibitionPlace place) {
    return _availableUsers.where((user) {
      bool categoryMatches = place.preferredCategories.contains(user.priceCategory);
      bool sizeMatches = user.preferredSize == place.size;
      return categoryMatches && sizeMatches;
    }).toList();
  }

  Future<void> _assignUserToPlace(String placeId, String userId,
      {PlaceStatus status = PlaceStatus.booked}) async {
    try {
      await FirebaseFirestore.instance
          .collection('exhibitions')
          .doc(widget.exhibitionId)
          .collection('places')
          .doc(placeId)
          .update({
        'assignedUserId': userId,
        'status': status.name,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Место успешно ${status == PlaceStatus.preliminary ? 'забронировано предварительно' : 'назначено'}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка назначения: $e')),
      );
    }
  }

  Future<void> _confirmPreliminary(String placeId) async {
    try {
      await FirebaseFirestore.instance
          .collection('exhibitions')
          .doc(widget.exhibitionId)
          .collection('places')
          .doc(placeId)
          .update({'status': PlaceStatus.booked.name});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Бронь подтверждена')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _unassignUser(String placeId) async {
    try {
      await FirebaseFirestore.instance
          .collection('exhibitions')
          .doc(widget.exhibitionId)
          .collection('places')
          .doc(placeId)
          .update({
        'assignedUserId': null,
        'status': PlaceStatus.free.name,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Место освобождено')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _confirmDeletePlace(String placeId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить место?'),
        content: const Text('Вы уверены? Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Нет'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Да'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('exhibitions')
          .doc(widget.exhibitionId)
          .collection('places')
          .doc(placeId)
          .delete();
      await FirebaseFirestore.instance
          .collection('exhibitions')
          .doc(widget.exhibitionId)
          .update({'capacity': FieldValue.increment(-1)});
    }
  }

  void _showAddPlaceDialog() async {
    final numberController = TextEditingController();
    double? selectedSize;
    List<String> selectedCategories = [];
    List<Map<String, dynamic>> allCategories = [];

    // Загружаем все категории
    try {
      allCategories = await _getAllCategories();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки категорий: $e')),
        );
      }
      return;
    }

    if (allCategories.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступных категорий. Сначала создайте категории.')),
        );
      }
      return;
    }

    // Получаем уникальные размеры из категорий
    final availableSizes = allCategories.map((cat) => cat['size'] as double).toSet().toList();
    availableSizes.sort();

    // Категории, отфильтрованные по выбранному размеру
    List<Map<String, dynamic>> filteredCategories = [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Добавить место'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: numberController,
                  decoration: const InputDecoration(labelText: 'Номер места'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<double>(
                  decoration: const InputDecoration(labelText: 'Выберите размер места'),
                  value: selectedSize,
                  items: availableSizes.map((size) {
                    return DropdownMenuItem(
                      value: size,
                      child: Text('$size м'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedSize = value;
                      // Фильтруем категории по выбранному размеру
                      filteredCategories = allCategories
                          .where((cat) => cat['size'] == selectedSize)
                          .toList();
                      selectedCategories.clear(); // сбрасываем выбранные категории при смене размера
                    });
                  },
                ),
                if (selectedSize != null && filteredCategories.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Выберите категории (можно несколько):'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: filteredCategories.map((category) {
                      final priceCategory = category['priceCategory'] as String;
                      final name = category['name'] as String;
                      return FilterChip(
                        label: Text('$name'),
                        selected: selectedCategories.contains(priceCategory),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              selectedCategories.add(priceCategory);
                            } else {
                              selectedCategories.remove(priceCategory);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ] else if (selectedSize != null && filteredCategories.isEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Нет категорий с выбранным размером', style: TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (numberController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Введите номер места')),
                  );
                  return;
                }
                if (selectedSize == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Выберите размер места')),
                  );
                  return;
                }
                if (selectedCategories.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Выберите хотя бы одну категорию')),
                  );
                  return;
                }

                // Вычисляем общую цену (опционально)
                double? totalPrice;
                for (var cat in filteredCategories) {
                  if (selectedCategories.contains(cat['priceCategory'])) {
                    if (cat['price'] != null) {
                      totalPrice = (totalPrice ?? 0) + (cat['price'] as double);
                    }
                  }
                }

                final newPlace = {
                  'number': numberController.text,
                  'size': selectedSize, // сохраняем выбранный размер
                  'preferredCategories': selectedCategories,
                  'price': totalPrice,
                  'status': PlaceStatus.free.name,
                  'assignedUserId': null,
                };
                try {
                  await FirebaseFirestore.instance
                      .collection('exhibitions')
                      .doc(widget.exhibitionId)
                      .collection('places')
                      .add(newPlace);
                  await FirebaseFirestore.instance
                      .collection('exhibitions')
                      .doc(widget.exhibitionId)
                      .update({'capacity': FieldValue.increment(1)});
                  Navigator.pop(context);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка при добавлении: $e')),
                  );
                }
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importFromExcel() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result == null) return;

    final bytes = result.files.single.bytes;
    if (bytes == null) return;

    var excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return;

    var sheet = excel.tables.values.first;
    if (sheet.rows.isEmpty) return;

    int addedCount = 0;
    for (int i = 1; i < sheet.rows.length; i++) {
      var row = sheet.rows[i];
      if (row.isEmpty || row.every((cell) => cell?.value == null)) continue;

      String number = row[0]?.value?.toString() ?? '';
      String sizeStr = row[1]?.value?.toString() ?? '';
      double? size = double.tryParse(sizeStr);
      if (size == null) continue;

      String categoriesStr = row[2]?.value?.toString() ?? '';
      List<String> categories = categoriesStr.split(',').map((e) => e.trim()).toList();
      double? price = double.tryParse(row[3]?.value?.toString() ?? '');
      String statusStr = row[4]?.value?.toString()?.toLowerCase() ?? 'free';
      PlaceStatus status = PlaceStatus.values.firstWhere(
        (e) => e.name == statusStr,
        orElse: () => PlaceStatus.free,
      );
      String? assignedUserId = row[5]?.value?.toString();

      if (number.isEmpty || categories.isEmpty) continue;

      await FirebaseFirestore.instance
          .collection('exhibitions')
          .doc(widget.exhibitionId)
          .collection('places')
          .add({
        'number': number,
        'size': size,
        'preferredCategories': categories,
        'price': price,
        'status': status.name,
        'assignedUserId': assignedUserId,
      });
      addedCount++;
    }

    if (addedCount > 0) {
      await FirebaseFirestore.instance
          .collection('exhibitions')
          .doc(widget.exhibitionId)
          .update({'capacity': FieldValue.increment(addedCount)});
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Импортировано мест: $addedCount')),
    );
  }

  Future<void> _uploadLayoutImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('exhibition_layouts')
        .child('${widget.exhibitionId}_${DateTime.now().millisecondsSinceEpoch}.jpg');

    try {
      await storageRef.putData(bytes);
      String downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('exhibitions')
          .doc(widget.exhibitionId)
          .update({'layoutImageUrl': downloadUrl});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Схема загружена')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки: $e')),
      );
    }
  }

  void _autoDistribute() async {
    if (_isLoadingUsers) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Подождите, данные загружаются...')),
      );
      return;
    }

    try {
      final placesSnapshot = await FirebaseFirestore.instance
          .collection('exhibitions')
          .doc(widget.exhibitionId)
          .collection('places')
          .get();

      final places = placesSnapshot.docs
          .map((doc) => ExhibitionPlace.fromFirestore(doc))
          .toList();

      final occupiedUserIds = places
          .where((place) => place.assignedUserId != null)
          .map((place) => place.assignedUserId!)
          .toSet();

      List<UserCategory> availableUsers = _availableUsers
          .where((user) => !occupiedUserIds.contains(user.userId))
          .toList();

      if (availableUsers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступных пользователей для распределения')),
        );
        return;
      }

      final freePlaces = places.where((place) => place.status == PlaceStatus.free).toList();

      if (freePlaces.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет свободных мест для распределения')),
        );
        return;
      }

      int assignedCount = 0;

      for (var place in freePlaces) {
        final suitableUsers = availableUsers.where((user) {
          return place.preferredCategories.contains(user.priceCategory) &&
              user.preferredSize == place.size;
        }).toList();

        if (suitableUsers.isNotEmpty) {
          final userToAssign = suitableUsers.first;
          await _assignUserToPlace(place.id, userToAssign.userId, status: PlaceStatus.preliminary);
          availableUsers.removeWhere((u) => u.userId == userToAssign.userId);
          assignedCount++;
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Автораспределение завершено. Назначено мест: $assignedCount')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при автораспределении: $e')),
      );
    }
  }

  void _showAssignUserDialog(ExhibitionPlace place) {
    final suitableUsers = _findSuitableUsers(place);
    if (suitableUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет подходящих пользователей для этого места')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите пользователя'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: suitableUsers.length,
            itemBuilder: (context, index) {
              final user = suitableUsers[index];
              return ListTile(
                title: Text(user.userId),
                subtitle: Text(user.type),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.hourglass_empty, color: Colors.blue),
                      onPressed: () {
                        Navigator.pop(context);
                        _assignUserToPlace(place.id, user.userId, status: PlaceStatus.preliminary);
                      },
                      tooltip: 'Предбронь',
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.green),
                      onPressed: () {
                        Navigator.pop(context);
                        _assignUserToPlace(place.id, user.userId, status: PlaceStatus.booked);
                      },
                      tooltip: 'Забронировать',
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.exhibitionName),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddPlaceDialog,
            tooltip: 'Добавить место',
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: _importFromExcel,
            tooltip: 'Импорт из Excel',
          ),
          IconButton(
            icon: const Icon(Icons.image),
            onPressed: _uploadLayoutImage,
            tooltip: 'Загрузить схему зала',
          ),
          IconButton(
            icon: const Icon(Icons.smart_button),
            onPressed: _autoDistribute,
            tooltip: 'Автораспределение',
          ),
        ],
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          if (_isLoadingUsers) const LinearProgressIndicator(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('exhibitions')
                  .doc(widget.exhibitionId)
                  .collection('places')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Ошибка: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final places = snapshot.data!.docs
                    .map((doc) => ExhibitionPlace.fromFirestore(doc))
                    .toList();

                if (places.isEmpty) {
                  return const Center(
                    child: Text('Нет доступных мест'),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: places.length,
                  itemBuilder: (context, index) {
                    final place = places[index];
                    return GestureDetector(
                      onTap: place.status == PlaceStatus.free
                          ? () => _showAssignUserDialog(place)
                          : null,
                      child: Card(
                        elevation: 4,
                        color: place.status == PlaceStatus.booked
                            ? Colors.green[50]
                            : place.status == PlaceStatus.preliminary
                                ? Colors.blue[50]
                                : Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Место ${place.number}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: place.status.color,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      place.status.displayName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                  if (place.status == PlaceStatus.free)
                                    IconButton(
                                      icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                                      onPressed: () => _confirmDeletePlace(place.id),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('Размер: ${place.size} м'),
                              Text('Категории: ${place.preferredCategories.join(', ')}'),
                              if (place.price != null) Text('Цена: ${place.price}₽'),
                              const SizedBox(height: 8),

                              // Если место занято или предбронь
                              if (place.status != PlaceStatus.free && place.assignedUserId != null)
                                FutureBuilder<DocumentSnapshot>(
                                  future: FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(place.assignedUserId)
                                      .get(),
                                  builder: (context, userSnapshot) {
                                    if (userSnapshot.connectionState == ConnectionState.waiting) {
                                      return const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 4),
                                        child: CircularProgressIndicator(),
                                      );
                                    }
                                    if (userSnapshot.hasError || !userSnapshot.hasData || !userSnapshot.data!.exists) {
                                      return const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 4),
                                        child: Text('Ошибка загрузки пользователя'),
                                      );
                                    }
                                    final userData = userSnapshot.data!.data() as Map<String, dynamic>;
                                    final userName = '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'.trim();
                                    return Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: place.status == PlaceStatus.preliminary
                                            ? Colors.blue[100]
                                            : Colors.green[100],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${place.status == PlaceStatus.preliminary ? "Предбронь" : "Назначен"}: $userName',
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                          Row(
                                            children: [
                                              if (place.status == PlaceStatus.preliminary)
                                                TextButton.icon(
                                                  onPressed: () => _confirmPreliminary(place.id),
                                                  icon: const Icon(Icons.check, size: 14),
                                                  label: const Text('Подтвердить', style: TextStyle(fontSize: 10)),
                                                  style: TextButton.styleFrom(
                                                    padding: EdgeInsets.zero,
                                                    minimumSize: const Size(50, 20),
                                                  ),
                                                ),
                                              TextButton.icon(
                                                onPressed: () => _unassignUser(place.id),
                                                icon: const Icon(Icons.close, size: 14),
                                                label: const Text('Освободить', style: TextStyle(fontSize: 10)),
                                                style: TextButton.styleFrom(
                                                  padding: EdgeInsets.zero,
                                                  minimumSize: const Size(50, 20),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}