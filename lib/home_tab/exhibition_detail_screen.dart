import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

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
  late Map<String, CategoryEntity> _categoriesById = {};
  final List<UserCategory> _availableUsers = [];
  bool _isLoadingUsers = false;

  PlaceStatus? _filterStatus;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAllCategoriesAndUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllCategoriesAndUsers() async {
    setState(() => _isLoadingUsers = true);
    try {
      // 1. Загружаем все категории: id -> объект
      final categoriesSnapshot = await FirebaseFirestore.instance
          .collection('categories')
          .get();

      _categoriesById.clear();
      for (final doc in categoriesSnapshot.docs) {
        final cat = CategoryEntity.fromFirestore(doc.id, doc);
        _categoriesById[doc.id] = cat;
      }

      // 2. Загружаем пользователей и их assignedCategories (по categoryId)
      final categoriesWithUsersSnapshot =
          await FirebaseFirestore.instance.collection('categories').get();

      final List<UserCategory> tempUsers = [];
      final Set<String> userIds = {};

      for (final doc in categoriesWithUsersSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final assignedUsers = List<String>.from(data['assignedUsers'] ?? []);

        for (final userId in assignedUsers) {
          userIds.add(userId);
          tempUsers.add(
            UserCategory(
              id: doc.id,
              type: data['name'] ?? '',
              categoryId: doc.id, // теперь тянем по id
              preferredSize:
                  (data['size'] as num?)?.toDouble() ?? 0.0,
              comment: null,
              userId: userId,
              userName: '',
            ),
          );
        }
      }

      if (userIds.isNotEmpty) {
        final usersSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where(
              FieldPath.documentId,
              whereIn: userIds.toList(),
            )
            .get();

        final Map<String, String> userNames = {};
        for (final doc in usersSnapshot.docs) {
          final data = doc.data();
          final firstName = data['firstName'] ?? '';
          final lastName = data['lastName'] ?? '';
          final fullName = '$firstName $lastName'.trim();
          userNames[doc.id] =
              fullName.isNotEmpty ? fullName : doc.id;
        }

        for (final user in tempUsers) {
          user.userName = userNames[user.userId] ?? user.userId;
        }
      } else {
        for (final user in tempUsers) {
          user.userName = user.userId;
        }
      }

      setState(() {
        _availableUsers.clear();
        _availableUsers.addAll(tempUsers);
        _isLoadingUsers = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Ошибка загрузки категорий: $e')),
        );
        setState(() => _isLoadingUsers = false);
      }
    }
  }

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
    const tolerableDelta = 0.1;

    return _availableUsers.where((user) {
      // 1. совпадение по categoryId (id документа категории)
      final userCategoryId = user.categoryId;

      // 2. place должен иметь эту категорию среди preferredCategoryIds
      if (!place.preferredCategoryIds.contains(userCategoryId)) {
        return false;
      }

      // 3. совпадение по размеру
      final sizeMatches =
          (user.preferredSize - place.size).abs() <=
              tolerableDelta;

      return sizeMatches;
    }).toList();
  }

  Future<void> _assignUserToPlace(String placeId, String userId, {PlaceStatus status = PlaceStatus.booked}) async {
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
            'Место успешно ${status == PlaceStatus.preliminary ? 'забронировано предварительно' : 'назначено'}',
          ),
        ),
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

  Future<bool> _isNumberTaken(String number) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('exhibitions')
        .doc(widget.exhibitionId)
        .collection('places')
        .where('number', isEqualTo: number)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  void _showAddPlaceDialog() async {
    final numberController = TextEditingController();
    final priceController = TextEditingController();
    double? selectedSize;
    List<String> selectedCategoryIds = []; // храним ID категорий
    List<Map<String, dynamic>> allCategories = [];

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

    final availableSizes = allCategories.map((cat) => cat['size'] as double).toSet().toList()..sort();
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
                TextField(
                  controller: priceController,
                  decoration: const InputDecoration(labelText: 'Цена (обязательно)'),
                  keyboardType: TextInputType.number,
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
                      filteredCategories = allCategories.where((cat) => cat['size'] == selectedSize).toList();
                      selectedCategoryIds.clear();
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
                      final id = category['id'] as String;
                      final name = category['name'] as String;
                      return FilterChip(
                        label: Text(name),
                        selected: selectedCategoryIds.contains(id),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              selectedCategoryIds.add(id);
                            } else {
                              selectedCategoryIds.remove(id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ] else if (selectedSize != null && filteredCategories.isEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Нет категорий с выбранным размером',
                    style: TextStyle(color: Colors.red),
                  ),
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

                final isTaken = await _isNumberTaken(numberController.text.trim());
                if (isTaken) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Такой номер места уже существует')),
                  );
                  return;
                }

                if (selectedSize == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Выберите размер места')),
                  );
                  return;
                }

                if (selectedCategoryIds.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Выберите хотя бы одну категорию')),
                  );
                  return;
                }

                final priceText = priceController.text.trim();
                if (priceText.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Введите цену')),
                  );
                  return;
                }

                final price = double.tryParse(priceText);
                if (price == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Цена должна быть числом')),
                  );
                  return;
                }

                try {
                  await FirebaseFirestore.instance
                      .collection('exhibitions')
                      .doc(widget.exhibitionId)
                      .collection('places')
                      .add({
                    'number': numberController.text.trim(),
                    'size': selectedSize,
                    'preferredCategoryIds': selectedCategoryIds, // обновлённое поле
                    'price': price,
                    'status': PlaceStatus.free.name,
                    'assignedUserId': null,
                  });

                  await FirebaseFirestore.instance
                      .collection('exhibitions')
                      .doc(widget.exhibitionId)
                      .update({'capacity': FieldValue.increment(1)});

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Место добавлено')),
                  );
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

  void _showExcelFormatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Формат Excel для импорта'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Файл должен содержать следующие колонки (первая строка — заголовок):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildExcelColumnInfo('A', 'Номер места', 'Текст', '12'),
              _buildExcelColumnInfo('B', 'Размер', 'Число', '4.5'),
              _buildExcelColumnInfo('C', 'ID категорий', 'Текст (через запятую)', 'cat123,cat456'),
              _buildExcelColumnInfo('D', 'Цена', 'Число (обязательно)', '10000'),
              _buildExcelColumnInfo('E', 'Статус (необязательно)', 'Текст', 'free / preliminary / booked'),
              _buildExcelColumnInfo('F', 'ID пользователя (необязательно)', 'Текст', 'user123'),
              const SizedBox(height: 12),
              const Text(
                'Пример строки (без заголовка):\n1\t4.5\tcat123,cat456\t10000\tfree\t',
                style: TextStyle(fontFamily: 'monospace'),
              ),
            ],
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

  Widget _buildExcelColumnInfo(String col, String label, String type, String example) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Text('$col:', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                Text('($type) Пример: $example', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importFromExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result == null) return;

    final bytes = result.files.single.bytes;
    if (bytes == null) return;

    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return;

    final sheet = excel.tables.values.first;
    if (sheet.rows.isEmpty) return;

    int addedCount = 0;
    int skippedCount = 0;

    for (int i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (row.isEmpty || row.every((cell) => cell?.value == null)) continue;

      final number = row[0]?.value?.toString().trim() ?? '';
      final sizeStr = row[1]?.value?.toString() ?? '';
      final size = double.tryParse(sizeStr);
      if (size == null) {
        skippedCount++;
        continue;
      }

      final categoriesStr = row[2]?.value?.toString() ?? '';
      final categoryIds = categoriesStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (number.isEmpty || categoryIds.isEmpty) {
        skippedCount++;
        continue;
      }

      final priceStr = row[3]?.value?.toString() ?? '';
      final price = double.tryParse(priceStr);
      if (price == null) {
        skippedCount++;
        continue;
      }

      final statusStr = row[4]?.value?.toString().toLowerCase() ?? 'free';
      final status = PlaceStatus.values.firstWhere(
        (e) => e.name == statusStr,
        orElse: () => PlaceStatus.free,
      );

      final assignedUserId = row.length > 5 ? row[5]?.value?.toString() : null;

      final duplicate = await _isNumberTaken(number);
      if (duplicate) {
        skippedCount++;
        continue;
      }

      await FirebaseFirestore.instance
          .collection('exhibitions')
          .doc(widget.exhibitionId)
          .collection('places')
          .add({
        'number': number,
        'size': size,
        'preferredCategoryIds': categoryIds, // обновлённое поле
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
      SnackBar(content: Text('Импортировано мест: $addedCount, пропущено: $skippedCount')),
    );
  }

  Future<void> _uploadLayoutImage() async {
    final result = await FilePicker.platform.pickFiles(
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
      final downloadUrl = await storageRef.getDownloadURL();
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

  Future<void> _exportToCsv() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('exhibitions')
          .doc(widget.exhibitionId)
          .collection('places')
          .get();

      final places = snapshot.docs.map((doc) => ExhibitionPlace.fromFirestore(doc)).toList();

      final buffer = StringBuffer();
      buffer.writeln('number,size,preferredCategoryIds,price,status,assignedUserId'); // обновлённый заголовок

      for (final place in places) {
        buffer.writeln(
          '"${place.number}","${place.size}","${place.preferredCategoryIds.join(',')}","${place.price}","${place.status.name}","${place.assignedUserId ?? ''}"',
        );
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/exhibition_places.csv');
      await file.writeAsString(buffer.toString(), encoding: utf8);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV экспортирован: ${file.path}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка экспорта: $e')),
      );
    }
  }

  Future<void> _autoDistribute() async {
    if (_isLoadingUsers) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Подождите, данные загружаются...')),
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
          const SnackBar(
              content:
                  Text('Нет доступных пользователей для распределения')),
        );
        return;
      }

      final freePlaces =
          places.where((place) => place.status == PlaceStatus.free).toList();

      if (freePlaces.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Нет свободных мест для распределения')),
        );
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      int assignedCount = 0;

      for (final place in freePlaces) {
        final suitableUsers = availableUsers.where((user) {
          const tolerableDelta = 0.1;

          final userCategoryId = user.categoryId;
          final placeMatchesCategory =
              place.preferredCategoryIds.contains(userCategoryId);

          final sizeMatches =
              (user.preferredSize - place.size).abs() <=
                  tolerableDelta;

          return placeMatchesCategory && sizeMatches;
        }).toList();

        if (suitableUsers.isNotEmpty) {
          final userToAssign = suitableUsers.first;
          final docRef = FirebaseFirestore.instance
              .collection('exhibitions')
              .doc(widget.exhibitionId)
              .collection('places')
              .doc(place.id);

          batch.update(docRef, {
            'assignedUserId': userToAssign.userId,
            'status': PlaceStatus.preliminary.name,
          });

          availableUsers
              .removeWhere((u) => u.userId == userToAssign.userId);
          assignedCount++;
        }
      }

      if (assignedCount > 0) {
        await batch.commit();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Автораспределение завершено. Назначено мест: $assignedCount')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Ошибка при автораспределении: $e')),
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
                title: Text(user.userName),
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
          IconButton(icon: const Icon(Icons.add), onPressed: _showAddPlaceDialog, tooltip: 'Добавить место'),
          IconButton(icon: const Icon(Icons.upload_file), onPressed: _importFromExcel, tooltip: 'Импорт из Excel'),
          IconButton(icon: const Icon(Icons.info_outline), onPressed: _showExcelFormatDialog, tooltip: 'Формат Excel'),
          IconButton(icon: const Icon(Icons.image), onPressed: _uploadLayoutImage, tooltip: 'Загрузить схему зала'),
          IconButton(icon: const Icon(Icons.smart_button), onPressed: _autoDistribute, tooltip: 'Автораспределение'),
          IconButton(icon: const Icon(Icons.download), onPressed: _exportToCsv, tooltip: 'Экспорт CSV'),
        ],
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          if (_isLoadingUsers) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Поиск по номеру',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<PlaceStatus?>(
                  value: _filterStatus,
                  hint: const Text('Статус'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Все')),
                    DropdownMenuItem(value: PlaceStatus.free, child: Text('Свободно')),
                    DropdownMenuItem(value: PlaceStatus.preliminary, child: Text('Предбронь')),
                    DropdownMenuItem(value: PlaceStatus.booked, child: Text('Забронировано')),
                  ],
                  onChanged: (value) => setState(() => _filterStatus = value),
                ),
              ],
            ),
          ),
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('exhibitions')
                .doc(widget.exhibitionId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>;
                final imageUrl = data['layoutImageUrl'] as String?;
                if (imageUrl != null && imageUrl.isNotEmpty) {
                  return Container(
                    height: 200,
                    margin: const EdgeInsets.all(8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(child: Icon(Icons.broken_image, size: 50)),
                      ),
                    ),
                  );
                }
              }
              return const SizedBox.shrink();
            },
          ),
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

                final places = snapshot.data!.docs.map((doc) => ExhibitionPlace.fromFirestore(doc)).toList();
                final query = _searchController.text.trim().toLowerCase();

                final filteredPlaces = places.where((place) {
                  final matchesSearch = query.isEmpty || place.number.toLowerCase().contains(query);
                  final matchesStatus = _filterStatus == null || place.status == _filterStatus;
                  return matchesSearch && matchesStatus;
                }).toList();

                if (filteredPlaces.isEmpty) {
                  return const Center(child: Text('Нет доступных мест'));
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: filteredPlaces.length,
                  itemBuilder: (context, index) {
                    final place = filteredPlaces[index];
                    return GestureDetector(
                      onTap: place.status == PlaceStatus.free ? () => _showAssignUserDialog(place) : null,
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
                                  Expanded(
                                    child: Text(
                                      'Место ${place.number}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: place.status.color,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      place.status.displayName,
                                      style: const TextStyle(color: Colors.white, fontSize: 10),
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
                              Text('Категории: ${place.preferredCategoryIds.join(', ')}'),
                              Text('Цена: ${place.price}₽'),
                              const SizedBox(height: 8),
                              if (place.status != PlaceStatus.free && place.assignedUserId != null)
                                FutureBuilder<DocumentSnapshot>(
                                  future: FirebaseFirestore.instance.collection('users').doc(place.assignedUserId).get(),
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
                                        color: place.status == PlaceStatus.preliminary ? Colors.blue[100] : Colors.green[100],
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