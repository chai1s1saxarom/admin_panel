import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CategoriesTab extends StatefulWidget {
  const CategoriesTab({Key? key}) : super(key: key);

  @override
  State<CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<CategoriesTab> {
  final CollectionReference _categoriesCollection =
      FirebaseFirestore.instance.collection('categories');

  // Получение следующего свободного номера (id)
  Future<String> _getNextId() async {
    final snapshot = await _categoriesCollection.get();
    int maxId = 0;
    for (var doc in snapshot.docs) {
      int? num = int.tryParse(doc.id);
      if (num != null && num > maxId) maxId = num;
    }
    return (maxId + 1).toString();
  }

  void _showAddCategoryDialog() {
    final nameController = TextEditingController();
    final priceCategoryController = TextEditingController();
    final sizeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новая категория'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Название категории'),
            ),
            TextField(
              controller: priceCategoryController,
              decoration: const InputDecoration(
                  labelText: 'Ценовая категория (Эконом, Стандарт, Премиум, VIP)'),
            ),
            TextField(
              controller: sizeController,
              decoration: const InputDecoration(
                  labelText: 'Размер (в метрах, например 2.5)'),
              keyboardType: TextInputType.number,
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
              final name = nameController.text.trim();
              final priceCategory = priceCategoryController.text.trim();
              final size = double.tryParse(sizeController.text.trim());
              if (name.isEmpty || priceCategory.isEmpty || size == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Заполните все поля корректно')),
                );
                return;
              }
              try {
                final newId = await _getNextId();
                await _categoriesCollection.doc(newId).set({
                  'name': name,
                  'priceCategory': priceCategory,
                  'size': size,
                  'assignedUsers': [], // пустой список пользователей
                  'createdAt': FieldValue.serverTimestamp(),
                });
                if (mounted) Navigator.pop(context);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка: $e')),
                  );
                }
              }
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  void _showAssignUsersDialog(String categoryId, Map<String, dynamic> categoryData) async {
    try {
      final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
      final users = usersSnapshot.docs;
      final currentAssigned = List<String>.from(categoryData['assignedUsers'] ?? []);
      List<String> selectedUserIds = List.from(currentAssigned);

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text('Пользователи категории "${categoryData['name']}"'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final user = users[index];
                  final userId = user.id;
                  final userData = user.data() as Map<String, dynamic>;
                  final userName = '${userData['firstName']} ${userData['lastName']}'.trim();
                  return CheckboxListTile(
                    title: Text(userName),
                    value: selectedUserIds.contains(userId),
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          selectedUserIds.add(userId);
                        } else {
                          selectedUserIds.remove(userId);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await _categoriesCollection.doc(categoryId).update({
                      'assignedUsers': selectedUserIds,
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                    if (mounted) Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Назначено ${selectedUserIds.length} пользователей')),
                    );
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ошибка: $e')),
                      );
                    }
                  }
                },
                child: const Text('Сохранить'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  void _showEditCategoryDialog(String id, Map<String, dynamic> data) {
    final nameController = TextEditingController(text: data['name'] ?? '');
    final priceCategoryController = TextEditingController(text: data['priceCategory'] ?? '');
    final sizeController = TextEditingController(text: (data['size'] ?? '').toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Редактировать категорию'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Название категории'),
            ),
            TextField(
              controller: priceCategoryController,
              decoration: const InputDecoration(labelText: 'Ценовая категория'),
            ),
            TextField(
              controller: sizeController,
              decoration: const InputDecoration(labelText: 'Размер (в метрах)'),
              keyboardType: TextInputType.number,
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
              final name = nameController.text.trim();
              final priceCategory = priceCategoryController.text.trim();
              final size = double.tryParse(sizeController.text.trim());
              if (name.isEmpty || priceCategory.isEmpty || size == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Заполните все поля корректно')),
                );
                return;
              }
              try {
                await _categoriesCollection.doc(id).update({
                  'name': name,
                  'priceCategory': priceCategory,
                  'size': size,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
                if (mounted) Navigator.pop(context);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка: $e')),
                  );
                }
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCategory(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить категорию?'),
        content: const Text('Пользователи, связанные с этой категорией, останутся без изменений.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _categoriesCollection.doc(id).delete();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Категории продуктов'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddCategoryDialog,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _categoriesCollection.orderBy('createdAt', descending: false).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Ошибка: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final categories = snapshot.data!.docs;
          if (categories.isEmpty) {
            return const Center(child: Text('Нет категорий. Нажмите + для добавления.'));
          }

          return ListView.builder(
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final doc = categories[index];
              final data = doc.data() as Map<String, dynamic>;
              final id = doc.id;
              final assignedUsersCount = (data['assignedUsers'] as List?)?.length ?? 0;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  title: Text('${data['name']} (№$id)'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ценовая категория: ${data['priceCategory'] ?? ''}'),
                      Text('Размер: ${data['size'] ?? ''} м'),
                      Text('Пользователей: $assignedUsersCount'),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.people),
                        onPressed: () => _showAssignUsersDialog(id, data),
                        tooltip: 'Назначить пользователей',
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _showEditCategoryDialog(id, data),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _deleteCategory(id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}