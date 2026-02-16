import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel;
import 'dart:typed_data';
import '../auth_service.dart'; // Импортируем ваш AuthService
import 'package:provider/provider.dart';

class UsersTab extends StatefulWidget {
  const UsersTab({Key? key}) : super(key: key);

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  final CollectionReference _usersCollection = 
      FirebaseFirestore.instance.collection('users');
  
  // Получаем AuthService через Provider
  AuthService get _authService => Provider.of<AuthService>(context, listen: false);

  void _showUserDetails(Map<String, dynamic> userData, String userId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => UserDetailsSheet(
        userData: userData,
        userId: userId,
        onUpdate: _updateUser,
        onDelete: _deleteUser,
      ),
    );
  }

  void _showCreateUserForm() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => CreateUserForm(
        onCreateUser: _createUserWithAuth,
      ),
    );
  }

  // Исправленный метод создания пользователя
  Future<void> _createUserWithAuth(Map<String, dynamic> userData, String password) async {
    // Показываем диалог загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // 1. Сохраняем данные текущего админа
      User? currentAdmin = FirebaseAuth.instance.currentUser;
      if (currentAdmin == null) {
        Navigator.pop(context); // Закрываем диалог загрузки
        throw Exception('Администратор не авторизован');
      }

      String adminEmail = currentAdmin.email!;
      
      // 2. Спрашиваем пароль админа для повторного входа
      Navigator.pop(context); // Закрываем диалог загрузки
      
      String? adminPassword = await _showAdminPasswordDialog();
      if (adminPassword == null) return;

      // Снова показываем загрузку
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // 3. Создаем нового пользователя в Authentication
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: userData['email'],
        password: password,
      );

      String uid = userCredential.user!.uid;

      // 4. Сохраняем данные в Firestore
      await _usersCollection.doc(uid).set({
        'userId': uid,
        'firstName': userData['firstName'],
        'lastName': userData['lastName'],
        'middleName': userData['middleName'],
        'passportSeriesNumber': userData['passportSeriesNumber'],
        'passportIssuedBy': userData['passportIssuedBy'],
        'telephone': userData['telephone'],
        'email': userData['email'].toLowerCase(),
        'emailVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'role': 'user',
      });

      // 5. Выходим из аккаунта нового пользователя
      await FirebaseAuth.instance.signOut();

      // 6. Возвращаемся в аккаунт админа
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: adminEmail,
        password: adminPassword,
      );

      // 7. Обновляем состояние AuthService (через stream это произойдет автоматически)
      
      Navigator.pop(context); // Закрываем диалог загрузки

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Пользователь успешно создан'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      Navigator.pop(context); // Закрываем диалог загрузки
      
      String errorMessage = 'Ошибка при создании: ';
      if (e.code == 'email-already-in-use') {
        errorMessage = 'Этот email уже используется';
      } else if (e.code == 'weak-password') {
        errorMessage = 'Слишком простой пароль';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'Некорректный email';
      } else {
        errorMessage += e.message ?? 'Неизвестная ошибка';
      }
      
      if (mounted) {
        _showErrorDialog(errorMessage);
      }
    } catch (e) {
      Navigator.pop(context); // Закрываем диалог загрузки
      
      if (mounted) {
        _showErrorDialog('Ошибка при создании: $e');
      }
    }
  }

  // Диалог для ввода пароля админа
  Future<String?> _showAdminPasswordDialog() async {
    TextEditingController passwordController = TextEditingController();
    bool obscurePassword = true;
    
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Подтверждение'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Для создания нового пользователя введите ваш пароль:',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Ваш пароль',
                      border: const OutlineInputBorder(),
                      hintText: 'Введите пароль',
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                      ),
                    ),
                    autofocus: true,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (passwordController.text.isNotEmpty) {
                      Navigator.pop(context, passwordController.text);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                  ),
                  child: const Text('Подтвердить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Диалог ошибки
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ошибка'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Остальные методы остаются без изменений...
  Future<void> _updateUser(String userId, Map<String, dynamic> userData) async {
    try {
      await _usersCollection.doc(userId).update({
        ...userData,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Пользователь обновлен'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при обновлении: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteUser(String userId) async {
    try {
      // Показываем диалог подтверждения
      bool? confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Удаление пользователя'),
          content: const Text('Вы уверены, что хотите удалить этого пользователя?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Удалить'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      // Удаляем из Firestore
      await _usersCollection.doc(userId).delete();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Пользователь удален'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при удалении: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _importFromExcel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result != null) {
        Uint8List fileBytes = result.files.single.bytes!;
        var excelFile = excel.Excel.decodeBytes(fileBytes);
        
        int successCount = 0;
        int errorCount = 0;
        List<String> errors = [];

        // Сохраняем данные админа
        User? currentAdmin = FirebaseAuth.instance.currentUser;
        if (currentAdmin == null) throw Exception('Администратор не авторизован');
        
        String adminEmail = currentAdmin.email!;
        String? adminPassword = await _showAdminPasswordDialog();
        if (adminPassword == null) return;

        // Показываем загрузку
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );

        for (var table in excelFile.tables.keys) {
          var sheet = excelFile.tables[table];
          if (sheet != null) {
            for (int i = 1; i < sheet.rows.length; i++) {
              var row = sheet.rows[i];
              if (row.length >= 5) {
                try {
                  String tempPassword = _generateTempPassword();
                  
                  // Создаем пользователя
                  UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
                    email: row[3]?.value?.toString() ?? '',
                    password: tempPassword,
                  );

                  String uid = userCredential.user!.uid;

                  await _usersCollection.doc(uid).set({
                    'userId': uid,
                    'firstName': row[0]?.value?.toString() ?? '',
                    'lastName': row[1]?.value?.toString() ?? '',
                    'middleName': row[2]?.value?.toString() ?? '',
                    'email': row[3]?.value?.toString() ?? '',
                    'telephone': row[4]?.value?.toString() ?? '',
                    'passportSeriesNumber': row.length > 5 ? row[5]?.value?.toString() : '',
                    'passportIssuedBy': row.length > 6 ? row[6]?.value?.toString() : '',
                    'emailVerified': false,
                    'role': 'user',
                    'createdAt': FieldValue.serverTimestamp(),
                    'updatedAt': FieldValue.serverTimestamp(),
                    'tempPassword': tempPassword,
                  });

                  // Выходим из нового пользователя
                  await FirebaseAuth.instance.signOut();
                  
                  // Возвращаемся в админа
                  await FirebaseAuth.instance.signInWithEmailAndPassword(
                    email: adminEmail,
                    password: adminPassword,
                  );
                  
                  successCount++;
                } catch (e) {
                  errorCount++;
                  errors.add('Строка ${i+1}: $e');
                }
              } else {
                errorCount++;
              }
            }
          }
        }

        Navigator.pop(context); // Закрываем загрузку

        if (mounted) {
          _showImportResult(successCount, errorCount, errors);
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Закрываем загрузку если была открыта
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при импорте: $e')),
        );
      }
    }
  }

  String _generateTempPassword() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    String password = 'Temp';
    for (int i = 0; i < 8; i++) {
      password += chars[(random + i) % chars.length];
    }
    return password;
  }

  void _showImportResult(int success, int errors, List<String> errorDetails) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Импорт завершен'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('✅ Успешно: $success'),
            Text('❌ Ошибок: $errors'),
            if (errorDetails.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Детали ошибок:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Container(
                height: 200,
                width: double.maxFinite,
                child: ListView.builder(
                  itemCount: errorDetails.length,
                  itemBuilder: (context, index) => Text(
                    errorDetails[index],
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showImportHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Импорт из Excel'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Файл Excel должен содержать следующие колонки в указанном порядке:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text('1. Имя *'),
              const Text('2. Фамилия *'),
              const Text('3. Отчество'),
              const Text('4. Email *'),
              const Text('5. Телефон *'),
              const Text('6. Серия и номер паспорта'),
              const Text('7. Кем выдан паспорт'),
              const SizedBox(height: 10),
              const Text('* - обязательные поля'),
              const SizedBox(height: 10),
              const Text('Первая строка считается заголовком и пропускается'),
              const SizedBox(height: 20),
              const Text(
                '⚠️ При импорте будет сгенерирован временный пароль для каждого пользователя',
                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Text(
                'Пример:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                color: Colors.grey[200],
                child: const Text(
                  'Иван,Иванов,Иванович,ivan@email.com,+79991234567,4510 123456,УВД г. Москвы\n'
                  'Петр,Петров,,petr@email.com,+79997654321,,',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: _usersCollection.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 60, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Ошибка: ${snapshot.error}'),
                ],
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data!.docs;

          if (users.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Нет пользователей',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Нажмите + чтобы добавить пользователя',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final userDoc = users[index];
              final userData = userDoc.data() as Map<String, dynamic>;
              final userId = userDoc.id;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.primaries[index % Colors.primaries.length],
                    child: Text(
                      _getInitials(userData),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    _getFullName(userData),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(userData['email'] ?? 'Нет email'),
                      if (userData['telephone'] != null && userData['telephone']!.isNotEmpty)
                        Text(
                          'Тел: ${userData['telephone']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                  isThreeLine: true,
                  onTap: () => _showUserDetails(userData, userId),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'import',
            onPressed: _importFromExcel,
            mini: true,
            tooltip: 'Импорт из Excel',
            child: const Icon(Icons.upload_file),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'help',
            onPressed: _showImportHelp,
            mini: true,
            tooltip: 'Помощь по импорту',
            child: const Icon(Icons.help_outline),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'create',
            onPressed: _showCreateUserForm,
            tooltip: 'Создать пользователя',
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  String _getFullName(Map<String, dynamic> userData) {
    final firstName = userData['firstName'] ?? '';
    final lastName = userData['lastName'] ?? '';
    final middleName = userData['middleName'] ?? '';
    
    if (firstName.isEmpty && lastName.isEmpty) return 'Без имени';
    
    String fullName = '$lastName $firstName'.trim();
    if (middleName.isNotEmpty) {
      fullName += ' $middleName';
    }
    return fullName;
  }

  String _getInitials(Map<String, dynamic> userData) {
    final firstName = userData['firstName'] ?? '';
    final lastName = userData['lastName'] ?? '';
    final middleName = userData['middleName'] ?? '';
    
    if (firstName.isEmpty && lastName.isEmpty) return '?';
    
    String initials = '';
    if (lastName.isNotEmpty) initials += lastName[0];
    if (firstName.isNotEmpty) initials += firstName[0];
    if (middleName.isNotEmpty) initials += middleName[0];
    
    return initials.toUpperCase();
  }
}

// Форма создания пользователя
class CreateUserForm extends StatefulWidget {
  final Function(Map<String, dynamic>, String) onCreateUser;

  const CreateUserForm({Key? key, required this.onCreateUser}) : super(key: key);

  @override
  State<CreateUserForm> createState() => _CreateUserFormState();
}

class _CreateUserFormState extends State<CreateUserForm> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _passportSeriesNumberController = TextEditingController();
  final _passportIssuedByController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        color: Colors.white,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  'Создать пользователя',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _lastNameController,
                decoration: const InputDecoration(
                  labelText: 'Фамилия *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Введите фамилию';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _firstNameController,
                decoration: const InputDecoration(
                  labelText: 'Имя *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Введите имя';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _middleNameController,
                decoration: const InputDecoration(
                  labelText: 'Отчество',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_add),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Введите email';
                  }
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                    return 'Введите корректный email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _telephoneController,
                decoration: const InputDecoration(
                  labelText: 'Телефон *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                  hintText: '+7 (999) 123-45-67',
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Введите телефон';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Пароль для нового пользователя *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                obscureText: _obscurePassword,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Введите пароль';
                  }
                  if (value.length < 6) {
                    return 'Пароль должен быть не менее 6 символов';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmPasswordController,
                decoration: InputDecoration(
                  labelText: 'Подтверждение пароля *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () {
                      setState(() {
                        _obscureConfirmPassword = !_obscureConfirmPassword;
                      });
                    },
                  ),
                ),
                obscureText: _obscureConfirmPassword,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Подтвердите пароль';
                  }
                  if (value != _passwordController.text) {
                    return 'Пароли не совпадают';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passportSeriesNumberController,
                decoration: const InputDecoration(
                  labelText: 'Серия и номер паспорта',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.credit_card),
                  hintText: '4510 123456',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passportIssuedByController,
                decoration: const InputDecoration(
                  labelText: 'Кем выдан паспорт',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_city),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitForm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Создать'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final userData = {
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'middleName': _middleNameController.text.trim(),
        'passportSeriesNumber': _passportSeriesNumberController.text.trim(),
        'passportIssuedBy': _passportIssuedByController.text.trim(),
        'telephone': _telephoneController.text.trim(),
        'email': _emailController.text.trim().toLowerCase(),
      };

      await widget.onCreateUser(userData, _passwordController.text);
      
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleNameController.dispose();
    _passportSeriesNumberController.dispose();
    _passportIssuedByController.dispose();
    _telephoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}


// Детальная информация о пользователе
class UserDetailsSheet extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String userId;
  final Function(String, Map<String, dynamic>) onUpdate;
  final Function(String) onDelete;

  const UserDetailsSheet({
    Key? key,
    required this.userData,
    required this.userId,
    required this.onUpdate,
    required this.onDelete,
  }) : super(key: key);

  @override
  State<UserDetailsSheet> createState() => _UserDetailsSheetState();
}

class _UserDetailsSheetState extends State<UserDetailsSheet> {
  bool _isEditing = false;
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _middleNameController;
  late TextEditingController _passportSeriesNumberController;
  late TextEditingController _passportIssuedByController;
  late TextEditingController _telephoneController;
  late TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    _firstNameController = TextEditingController(text: widget.userData['firstName'] ?? '');
    _lastNameController = TextEditingController(text: widget.userData['lastName'] ?? '');
    _middleNameController = TextEditingController(text: widget.userData['middleName'] ?? '');
    _passportSeriesNumberController = TextEditingController(text: widget.userData['passportSeriesNumber'] ?? '');
    _passportIssuedByController = TextEditingController(text: widget.userData['passportIssuedBy'] ?? '');
    _telephoneController = TextEditingController(text: widget.userData['telephone'] ?? '');
    _emailController = TextEditingController(text: widget.userData['email'] ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            color: Colors.white,
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Информация о пользователе',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(_isEditing ? Icons.close : Icons.edit),
                        onPressed: () {
                          setState(() {
                            _isEditing = !_isEditing;
                            if (!_isEditing) {
                              _initializeControllers(); // Сброс изменений
                            }
                          });
                        },
                      ),
                      if (_isEditing)
                        IconButton(
                          icon: const Icon(Icons.save),
                          onPressed: _saveChanges,
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: _confirmDelete,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _isEditing
                    ? _buildEditForm(scrollController)
                    : _buildInfoDisplay(scrollController),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoDisplay(ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      children: [
        Center(
          child: CircleAvatar(
            radius: 50,
            backgroundColor: Colors.blue,
            child: Text(
              _getInitials(),
              style: const TextStyle(
                fontSize: 24,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            _getFullName(),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (widget.userData['role'] != null)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: widget.userData['role'] == 'admin' 
                    ? Colors.purple[50] 
                    : Colors.blue[50],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                widget.userData['role'] == 'admin' ? 'Администратор' : 'Пользователь',
                style: TextStyle(
                  color: widget.userData['role'] == 'admin' 
                      ? Colors.purple[800] 
                      : Colors.blue[800],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),
        _buildInfoTile(Icons.email, 'Email', widget.userData['email']),
        _buildInfoTile(Icons.phone, 'Телефон', widget.userData['telephone'] ?? 'Не указан'),
        _buildInfoTile(Icons.credit_card, 'Паспорт', 
            widget.userData['passportSeriesNumber'] ?? 'Не указан'),
        _buildInfoTile(Icons.location_city, 'Кем выдан', 
            widget.userData['passportIssuedBy'] ?? 'Не указан'),
        if (widget.userData['emailVerified'] != null)
          _buildInfoTile(
            Icons.verified_user,
            'Email подтвержден',
            widget.userData['emailVerified'] ? 'Да' : 'Нет',
          ),
        if (widget.userData['createdAt'] != null)
          _buildInfoTile(
            Icons.calendar_today,
            'Дата регистрации',
            _formatDate(widget.userData['createdAt']),
          ),
        if (widget.userData['updatedAt'] != null)
          _buildInfoTile(
            Icons.update,
            'Последнее обновление',
            _formatDate(widget.userData['updatedAt']),
          ),
      ],
    );
  }

  Widget _buildEditForm(ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      children: [
        TextFormField(
          controller: _lastNameController,
          decoration: const InputDecoration(
            labelText: 'Фамилия',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _firstNameController,
          decoration: const InputDecoration(
            labelText: 'Имя',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _middleNameController,
          decoration: const InputDecoration(
            labelText: 'Отчество',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _emailController,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _telephoneController,
          decoration: const InputDecoration(
            labelText: 'Телефон',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _passportSeriesNumberController,
          decoration: const InputDecoration(
            labelText: 'Серия и номер паспорта',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _passportIssuedByController,
          decoration: const InputDecoration(
            labelText: 'Кем выдан паспорт',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveChanges() async {
    final updatedData = {
      'firstName': _firstNameController.text.trim(),
      'lastName': _lastNameController.text.trim(),
      'middleName': _middleNameController.text.trim(),
      'passportSeriesNumber': _passportSeriesNumberController.text.trim(),
      'passportIssuedBy': _passportIssuedByController.text.trim(),
      'telephone': _telephoneController.text.trim(),
      'email': _emailController.text.trim().toLowerCase(),
    };

    await widget.onUpdate(widget.userId, updatedData);
    setState(() => _isEditing = false);
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удаление пользователя'),
        content: const Text('Вы уверены, что хотите удалить этого пользователя?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.onDelete(widget.userId);
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  String _getFullName() {
    final firstName = widget.userData['firstName'] ?? '';
    final lastName = widget.userData['lastName'] ?? '';
    final middleName = widget.userData['middleName'] ?? '';
    
    if (firstName.isEmpty && lastName.isEmpty) return 'Без имени';
    
    String fullName = '$lastName $firstName'.trim();
    if (middleName.isNotEmpty) {
      fullName += ' $middleName';
    }
    return fullName;
  }

  String _getInitials() {
    final firstName = widget.userData['firstName'] ?? '';
    final lastName = widget.userData['lastName'] ?? '';
    final middleName = widget.userData['middleName'] ?? '';
    
    if (firstName.isEmpty && lastName.isEmpty) return '?';
    
    String initials = '';
    if (lastName.isNotEmpty) initials += lastName[0];
    if (firstName.isNotEmpty) initials += firstName[0];
    if (middleName.isNotEmpty) initials += middleName[0];
    
    return initials.toUpperCase();
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Неизвестно';
    if (timestamp is Timestamp) {
      final date = timestamp.toDate();
      return '${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute}';
    }
    return 'Неизвестно';
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleNameController.dispose();
    _passportSeriesNumberController.dispose();
    _passportIssuedByController.dispose();
    _telephoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}