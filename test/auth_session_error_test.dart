import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komet/core/protocol/packet.dart';

void main() {
  group('обрыв связи не должен стоить пользователю нового кода', () {
    test('клиентская ошибка "сессия не онлайн" — токен переиспользуем', () {
      final error = StateError(
        'AccountModule: сессия не онлайн (текущее состояние: connecting)',
      );

      expect(isSessionStateError(error), isTrue);
      expect(isAuthSessionLostError(error), isFalse);
    });

    test('таймаут запроса — токен переиспользуем', () {
      const error = PacketError('AUTH таймаут');

      expect(isAuthSessionLostError(error), isFalse);
      expect(isSessionStateError(error), isFalse);
    });
  });

  group('мёртвая авторизационная сессия требует нового кода', () {
    test('FAIL_LOGIN_TOKEN приходит как SessionExpiredException', () {
      const error = SessionExpiredException(
        'Ваш токен был отклонён сервером, хм... Попробуйте войти ещё раз.',
      );

      expect(isAuthSessionLostError(error), isTrue);
    });

    test('сервер сообщает, что авторизационная сессия потеряна', () {
      const lost = PacketError('Авторизационная сессия не найдена');
      const missing = PacketError('Сессия не найдена');

      expect(isAuthSessionLostError(lost), isTrue);
      expect(isAuthSessionLostError(missing), isTrue);
    });
  });

  group('ошибка самого кода не трогает токен', () {
    test('неверный код — ни восстановление, ни перезапрос', () {
      const error = PacketError('Неверный код');

      expect(isAuthSessionLostError(error), isFalse);
      expect(isSessionStateError(error), isFalse);
    });

    test('исчерпаны попытки — ни восстановление, ни перезапрос', () {
      const error = PacketError('Слишком много попыток, попробуйте позже');

      expect(isAuthSessionLostError(error), isFalse);
      expect(isSessionStateError(error), isFalse);
    });
  });

  group('cached chats are blocked only on a rejected saved login', () {
    test(
      'an explicit LOGIN rejection or expired token blocks cached chats',
      () {
        expect(
          isSavedLoginRejection(
            const PacketError('synthetic denied login'),
            loginWasRejected: true,
          ),
          isTrue,
        );
        expect(
          isSavedLoginRejection(
            const SessionExpiredException('synthetic expired session'),
            loginWasRejected: false,
          ),
          isTrue,
        );
      },
    );

    test('transient failures and post-login packet errors preserve cache', () {
      expect(
        isSavedLoginRejection(
          const PacketError('synthetic not ready', errorKey: 'login.not.ready'),
          loginWasRejected: true,
        ),
        isFalse,
      );
      expect(
        isSavedLoginRejection(
          TimeoutException('synthetic timeout'),
          loginWasRejected: false,
        ),
        isFalse,
      );
      expect(
        isSavedLoginRejection(
          const PacketError('synthetic profile sync failure'),
          loginWasRejected: false,
        ),
        isFalse,
      );
    });
  });
}
