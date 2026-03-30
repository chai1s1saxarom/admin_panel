import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import '/home_tab/users_tab.dart';
import '/home_tab/categories_tab.dart';
import '/home_tab/exgibition_tab.dart'; // Проверьте имя файла!

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    return StreamBuilder<User?>(
      stream: authService.userStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data;
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text('Главная'),
              actions: [
                IconButton(
                  icon: Icon(Icons.logout),
                  onPressed: () async {
                    try {
                      await authService.signOut();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ошибка выхода: $e')),
                      );
                    }
                  },
                ),
              ],
              bottom: TabBar(
                tabs: [
                  Tab(text: 'Пользователи'),
                  Tab(text: 'Выставки'),
                  Tab(text: 'Типы товаров'),
                ],
              ),
            ),
            body: user == null
                ? Center(child: Text('Войдите в систему'))
                : TabBarView(
                    children: [
                      UsersTab(),
                      ExhibitionsTab(),
                      CategoriesTab(),
                    ],
                  ),
          ),
        );
      },
    );
  }
}