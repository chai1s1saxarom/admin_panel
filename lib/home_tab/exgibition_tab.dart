import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ---------- Модели данных ----------
class ExhibitionPlace {
  final String id;
  final String number;
  final List<String> preferredCategories;
  final String size;
  final bool isBooked;
  final double? price;
  final String? assignedUserId;

  ExhibitionPlace({
    required this.id,
    required this.number,
    required this.preferredCategories,
    required this.size,
    required this.isBooked,
    this.price,
    this.assignedUserId,
  });

  factory ExhibitionPlace.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ExhibitionPlace(
      id: doc.id,
      number: data['number'] ?? '',
      preferredCategories: List<String>.from(data['preferredCategories'] ?? []),
      size: data['size'] ?? '',
      isBooked: data['isBooked'] ?? false,
      price: (data['price'] as num?)?.toDouble(),
      assignedUserId: data['assignedUserId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'number': number,
      'preferredCategories': preferredCategories,
      'size': size,
      'isBooked': isBooked,
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

// ---------- Таб с выставками ----------
class ExhibitionsTab extends StatelessWidget {
  const ExhibitionsTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('exhibitions').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Ошибка: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final exhibitions = snapshot.data!.docs;

        return ListView.builder(
          itemCount: exhibitions.length,
          itemBuilder: (context, index) {
            final exDoc = exhibitions[index];
            final exData = exDoc.data() as Map<String, dynamic>;
            
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: Text(
                  exData['name'] ?? 'Без названия',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text('📅 ${_formatDate(exData['startDate'])} - ${_formatDate(exData['endDate'])}'),
                    Text('📍 Количество мест: ${exData['capacity']}'),
                    Text('💰 Статус: ${exData['isActive'] ?? true ? 'Активна' : 'Завершена'}'),
                  ],
                ),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ExhibitionDetailScreen(
                        exhibitionId: exDoc.id,
                        exhibitionName: exData['name'] ?? 'Выставка',
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return '-';
    
    if (date is Timestamp) {
      DateTime dateTime = date.toDate();
      return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year}';
    }
    
    if (date is DateTime) {
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    }
    
    if (date is String) {
      return date.isEmpty ? '-' : date;
    }
    
    return '-';
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
        snapshot.docs.map((doc) => UserCategory.fromFirestore(doc))
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
      // Проверяем соответствие категории
      bool categoryMatches = place.preferredCategories.contains(user.priceCategory);
      
      // Проверяем соответствие размера
      bool sizeMatches = user.preferredSize == place.size;
      
      // Пользователь подходит, если совпадает категория И размер
      // (можно изменить логику по необходимости)
      return categoryMatches && sizeMatches;
    }).toList();
  }

  Future<void> _assignUserToPlace(String placeId, String userId) async {
    try {
      await FirebaseFirestore.instance
          .collection('exhibitions')
          .doc(widget.exhibitionId)
          .collection('places')
          .doc(placeId)
          .update({
            'assignedUserId': userId,
            'isBooked': true,
          });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Место успешно назначено')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка назначения: $e')),
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
            'isBooked': false,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.exhibitionName),
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
                      color: place.isBooked ? Colors.blue[50] : Colors.white,
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
                                    color: place.isBooked ? Colors.green : Colors.orange,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    place.isBooked ? 'Занято' : 'Свободно',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('Размер: ${place.size}'),
                            Text('Категории: ${place.preferredCategories.join(', ')}'),
                            if (place.price != null) 
                              Text('Цена: ${place.price}₽'),
                            const SizedBox(height: 8),
                            if (place.isBooked && place.assignedUserId != null)
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
                                        color: Colors.green[100],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Назначен: ${userData['type'] ?? 'Неизвестно'}',
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                          if (place.assignedUserId != null)
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
                                    );
                                  }
                                  return const Text('Загрузка...');
                                },
                              ),
                            if (!place.isBooked && suitableUsers.isNotEmpty)
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
                                          IconButton(
                                            icon: const Icon(Icons.add_circle, size: 16, color: Colors.green),
                                            onPressed: () => _assignUserToPlace(place.id, user.id),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            if (!place.isBooked && suitableUsers.isEmpty)
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