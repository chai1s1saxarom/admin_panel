import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'exhibition_detail_screen.dart';

class ExhibitionsTab extends StatelessWidget {
  const ExhibitionsTab({Key? key}) : super(key: key);

  String _formatDate(DateTime date) => DateFormat('dd.MM.yyyy').format(date);

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
                      if (picked != null) setState(() => startDate = picked);
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
                      if (picked != null) setState(() => endDate = picked);
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
}