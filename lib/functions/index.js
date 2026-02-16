const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.createUser = functions.https.onCall(async (data, context) => {
  // Проверяем, что запрос от авторизованного пользователя
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Пользователь должен быть авторизован'
    );
  }

  // Проверяем, что пользователь - администратор
  const adminDoc = await admin.firestore()
    .collection('users')
    .doc(context.auth.uid)
    .get();

  const userRole = adminDoc.data()?.role;
  
  if (userRole !== 'admin') {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Только администратор может создавать пользователей'
    );
  }

  try {
    // Создаем пользователя в Authentication
    const userRecord = await admin.auth().createUser({
      email: data.email,
      password: data.password,
      emailVerified: false,
    });

    // Сохраняем дополнительные данные в Firestore
    await admin.firestore()
      .collection('users')
      .doc(userRecord.uid)
      .set({
        userId: userRecord.uid,
        firstName: data.firstName,
        lastName: data.lastName,
        middleName: data.middleName || '',
        passportSeriesNumber: data.passportSeriesNumber || '',
        passportIssuedBy: data.passportIssuedBy || '',
        telephone: data.telephone,
        email: data.email.toLowerCase(),
        emailVerified: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        role: 'user',
      });

    return {
      success: true,
      uid: userRecord.uid,
      message: 'Пользователь успешно создан'
    };
  } catch (error) {
    console.error('Ошибка при создании пользователя:', error);
    
    if (error.code === 'auth/email-already-exists') {
      throw new functions.https.HttpsError(
        'already-exists',
        'Пользователь с таким email уже существует'
      );
    }
    
    throw new functions.https.HttpsError(
      'internal',
      'Ошибка при создании пользователя: ' + error.message
    );
  }
});