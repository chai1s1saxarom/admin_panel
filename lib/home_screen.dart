import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:excel/excel.dart' hide Border; 
import '/home_tab/users_tab.dart';
import '/home_tab/exgibition_tab.dart';
class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.user;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Главная'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await authService.signOut();
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Пользователи'), //import from users_tab
              Tab(text: 'Выставки'),   //import from exgibition_tab
              Tab(text: 'Типы товаров'),
            ],
          ),
        ),
        body: user == null
            ? const Center(child: Text('Войдите в систему'))
            : const TabBarView(
                children: [
                  UsersTab(),
                  ExhibitionsTab(),
                  _ProductTypesTab(),
                ],
              ),
      ),
    );
  }
}


// ---------- Таб с типами товаров ----------
class _ProductTypesTab extends StatelessWidget {
  const _ProductTypesTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('product_types').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Ошибка: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final types = snapshot.data!.docs;

        return ListView.builder(
          itemCount: types.length,
          itemBuilder: (context, index) {
            final typeDoc = types[index];
            final typeData = typeDoc.data() as Map<String, dynamic>;
            return ListTile(
              leading: const Icon(Icons.category),
              title: Text(typeData['name'] ?? 'Без названия'),
            );
          },
        );
      },
    );
  }


}