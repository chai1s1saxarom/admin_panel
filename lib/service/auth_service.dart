import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? _user;
  bool _isLoading = false;

  AuthService() {
    _loadUser();
  }

  bool get isLoading => _isLoading;
  User? get user => _user;
  
  // Stream для отслеживания состояния авторизации
  Stream<User?> get userStream => _auth.authStateChanges();

  // Загрузка сохраненного пользователя
  Future<void> _loadUser() async {
    try {
      _isLoading = true;
      notifyListeners();

      // Проверяем, есть ли сохраненная сессия в SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final hasLoggedIn = prefs.getBool('hasLoggedIn') ?? false;

      if (hasLoggedIn) {
        // Если есть сохраненная сессия, пробуем восстановить пользователя
        _user = _auth.currentUser;
        
        // Если пользователь не восстановился автоматически, пробуем обновить токен
        if (_user == null) {
          await _auth.authStateChanges().first;
          _user = _auth.currentUser;
        }
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      print('Error loading user: $e');
    }
  }

  // Вход с email и паролем
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      _isLoading = true;
      notifyListeners();

      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      await _saveLoginStatus();
      _user = userCredential.user;
      
      _isLoading = false;
      notifyListeners();
      return _user;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  // Вход через Google (добавьте firebase_auth_web: ^5.10.3 и google_sign_in: ^6.1.5)
  // Future<User?> signInWithGoogle() async { ... }

  // Сохранение статуса входа
  Future<void> _saveLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasLoggedIn', true);
  }

  // Выход
  Future<void> signOut() async {
    try {
      _isLoading = true;
      notifyListeners();

      await _auth.signOut();
      
      // Очищаем сохраненный статус
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('hasLoggedIn');
      
      _user = null;
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  // Отправка письма для сброса пароля
  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // Получение текущего пользователя
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  // Проверка, авторизован ли пользователь
  bool isLoggedIn() {
    return _auth.currentUser != null;
  }
}