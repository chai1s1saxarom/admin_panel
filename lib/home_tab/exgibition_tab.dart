import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';

// ---------- Модели данных ----------

// Статус места
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
  final String size;
  final PlaceStatus status; // Заменяет isBooked
  final double? price;
  final String? assignedUserId; // Для предброни и брони

  ExhibitionPlace({
    required this.id,
    required this.number,
    required this.preferredCategories,
    required this.size,
    required this.status,
    this.price,
    this.assignedUserId,
  });

  // Для обратной совместимости с isBooked
  bool get isBooked => status == PlaceStatus.booked;

  factory ExhibitionPlace.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    // Получаем статус из строки или числа (для совместимости)
    PlaceStatus status;
    if (data['status'] is String) {
      status = PlaceStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => PlaceStatus.free,
      );
    } else if (data['isBooked'] == true) {
      status = PlaceStatus.booked; // старая запись
    } else {
      status = PlaceStatus.free;
    }
    return ExhibitionPlace(
      id: doc.id,
      number: data['number'] ?? '',
      preferredCategories: List<String>.from(data['preferredCategories'] ?? []),
      size: data['size'] ?? '',
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
      'status': status.name, // сохраняем строку
      'price': price,
      'assignedUserId': assignedUserId,
    };
  }
}

class UserCategory {
  final String id;
  final String type;
  final String priceCategory;
  final String preferredSize;
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

  factory UserCategory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserCategory(
      id: doc.id,
      type: data['type'] ?? '',
      priceCategory: data['priceCategory'] ?? '',
      preferredSize: data['preferredSize'] ?? '',
      comment: data['comment'],
      userId: data['userId'] ?? '',
    );
  }
}

class Exhibition {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final int capacity;
  final String? layoutImageUrl; // Ссылка на схему зала
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
          .collection('userCategories')
          .get();

      _availableUsers.clear();
      _availableUsers.addAll(
        snapshot.docs.map((doc) => UserCategory.fromFirestore(doc)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки пользователей: $e')),
      );
    } finally {
      setState(() => _isLoadingUsers = false);
    }
  }

  List<UserCategory> _findSuitableUsers(ExhibitionPlace place) {
    return _availableUsers.where((user) {
      bool categoryMatches = place.preferredCategories.contains(user.priceCategory);
      bool sizeMatches = user.preferredSize == place.size;
      return categoryMatches && sizeMatches;
    }).toList();
  }

  // Назначение пользователя с указанием статуса
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
        SnackBar(content: Text('Место успешно ${status == PlaceStatus.preliminary ? 'забронировано предварительно' : 'назначено'}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка назначения: $e')),
      );
    }
  }

  // Перевод предброни в бронь
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

  // Диалог добавления одного места (с выбором статуса)
  void _showAddPlaceDialog() {
    final numberController = TextEditingController();
    String selectedSize = 'Маленький';
    List<String> selectedCategories = [];
    final priceController = TextEditingController();
    PlaceStatus selectedStatus = PlaceStatus.free;

    final List<String> categoryOptions = ['Эконом', 'Стандарт', 'Премиум', 'VIP'];

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
                DropdownButtonFormField<String>(
                  value: selectedSize,
                  items: ['Маленький', 'Средний', 'Большой']
                      .map((size) => DropdownMenuItem(value: size, child: Text(size)))
                      .toList(),
                  onChanged: (val) => setState(() => selectedSize = val!),
                  decoration: const InputDecoration(labelText: 'Размер'),
                ),
                DropdownButtonFormField<String>(
                  value: selectedCategories.isNotEmpty ? selectedCategories.first : null,
                  items: categoryOptions.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        if (selectedCategories.contains(val)) {
                          selectedCategories.remove(val);
                        } else {
                          selectedCategories.add(val);
                        }
                      });
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Категории (нажмите для выбора)'),
                ),
                Wrap(
                  children: selectedCategories.map((cat) => Chip(
                    label: Text(cat),
                    onDeleted: () => setState(() => selectedCategories.remove(cat)),
                  )).toList(),
                ),
                TextField(
                  controller: priceController,
                  decoration: const InputDecoration(labelText: 'Цена (необязательно)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<PlaceStatus>(
                  value: selectedStatus,
                  items: PlaceStatus.values.map((status) {
                    return DropdownMenuItem(
                      value: status,
                      child: Text(status.displayName),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => selectedStatus = val!),
                  decoration: const InputDecoration(labelText: 'Статус'),
                ),
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
                if (numberController.text.isEmpty || selectedCategories.isEmpty) return;
                final newPlace = {
                  'number': numberController.text,
                  'size': selectedSize,
                  'preferredCategories': selectedCategories,
                  'price': priceController.text.isNotEmpty ? double.tryParse(priceController.text) : null,
                  'status': selectedStatus.name,
                  'assignedUserId': null,
                };
                await FirebaseFirestore.instance
                    .collection('exhibitions')
                    .doc(widget.exhibitionId)
                    .collection('places')
                    .add(newPlace);
                // Увеличим capacity
                await FirebaseFirestore.instance
                    .collection('exhibitions')
                    .doc(widget.exhibitionId)
                    .update({'capacity': FieldValue.increment(1)});
                Navigator.pop(context);
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
  }

  // Импорт мест из Excel
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

    // Берём первый лист
    var sheet = excel.tables.values.first;
    if (sheet.rows.isEmpty) return;

    // Предполагаемые заголовки: Номер, Размер, Категории, Цена, Статус, ID пользователя
    // Можно сделать проверку заголовков, но для простоты пропустим первую строку
    int addedCount = 0;
    for (int i = 1; i < sheet.rows.length; i++) {
      var row = sheet.rows[i];
      if (row.isEmpty || row.every((cell) => cell?.value == null)) continue;

      String number = row[0]?.value?.toString() ?? '';
      String size = row[1]?.value?.toString() ?? 'Маленький';
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

    // Обновим capacity
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

  // Загрузка схемы зала (изображения)
  Future<void> _uploadLayoutImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    // Загружаем в Firebase Storage
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('exhibition_layouts')
        .child('${widget.exhibitionId}_${DateTime.now().millisecondsSinceEpoch}.jpg');

    try {
      await storageRef.putData(bytes);
      String downloadUrl = await storageRef.getDownloadURL();

      // Сохраняем ссылку в документе выставки
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

  // Заглушка для автораспределения
  void _autoDistribute() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Функция автораспределения в разработке')),
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
          if (_isLoadingUsers)
            const LinearProgressIndicator(),
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
                    final suitableUsers = _findSuitableUsers(place);

                    return Card(
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
                            Text('Размер: ${place.size}'),
                            Text('Категории: ${place.preferredCategories.join(', ')}'),
                            if (place.price != null)
                              Text('Цена: ${place.price}₽'),
                            const SizedBox(height: 8),

                            // Если место занято или предбронь
                            if (place.status != PlaceStatus.free && place.assignedUserId != null)
                              FutureBuilder<DocumentSnapshot>(
                                future: FirebaseFirestore.instance
                                    .collection('userCategories')
                                    .doc(place.assignedUserId)
                                    .get(),
                                builder: (context, userSnapshot) {
                                  if (userSnapshot.hasData && userSnapshot.data!.exists) {
                                    final userData = userSnapshot.data!.data() as Map<String, dynamic>;
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
                                            '${place.status == PlaceStatus.preliminary ? "Предбронь" : "Назначен"}: ${userData['type'] ?? 'Неизвестно'}',
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
                                  }
                                  return const Text('Загрузка...');
                                },
                              ),

                            // Для свободных мест показываем подходящих пользователей
                            if (place.status == PlaceStatus.free && suitableUsers.isNotEmpty)
                              Expanded(
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: suitableUsers.length,
                                  itemBuilder: (context, userIndex) {
                                    final user = suitableUsers[userIndex];
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 2),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${user.type}',
                                              style: const TextStyle(fontSize: 10),
                                            ),
                                          ),
                                          // Кнопка "Предварительно забронировать"
                                          IconButton(
                                            icon: const Icon(Icons.hourglass_empty, size: 16, color: Colors.blue),
                                            onPressed: () => _assignUserToPlace(
                                              place.id,
                                              user.id,
                                              status: PlaceStatus.preliminary,
                                            ),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            tooltip: 'Предбронь',
                                          ),
                                          // Кнопка "Забронировать сразу"
                                          IconButton(
                                            icon: const Icon(Icons.add_circle, size: 16, color: Colors.green),
                                            onPressed: () => _assignUserToPlace(
                                              place.id,
                                              user.id,
                                              status: PlaceStatus.booked,
                                            ),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            tooltip: 'Забронировать',
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            if (place.status == PlaceStatus.free && suitableUsers.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(4),
                                child: Text(
                                  'Нет подходящих пользователей',
                                  style: TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                              ),
                          ],
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