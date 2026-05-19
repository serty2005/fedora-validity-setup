# PAM, sudo, GNOME и GDM

Эта интеграция подключает уже работающий service layer к штатному Fedora
PAM/authselect пути. Она не заменяет пароль, не удаляет stock `fprintd`,
`fprintd-pam` или `libfprint` и не редактирует `/etc/pam.d` вручную.

## Предварительные условия

Сначала должен быть зелёный service layer:

```bash
./scripts/check-dbus-chain.sh --wait 20
./scripts/stability-check.sh --verify "$USER"
```

Если эти команды не проходят, не переходить к PAM/GDM/sudo. Сначала
восстановить `open-fprintd.service`, `python3-validity.service`,
D-Bus ownership и `fprintd-list`.

## Диагностика текущего состояния

Read-only snapshot:

```bash
./scripts/check-pam-state.sh
```

С физической проверкой:

```bash
./scripts/check-pam-state.sh --verify "$USER"
```

Скрипт показывает:

- `authselect current`;
- где найден `pam_fprintd.so` в `/etc/pam.d` и `/etc/authselect`;
- версии `fprintd`, `fprintd-pam`, `libfprint`;
- состояние `open-fprintd.service` и `python3-validity.service`;
- результат `check-dbus-chain.sh --wait 20`;
- `fprintd-list "$USER"`;
- `fprintd-verify "$USER"` только с `--verify`.

Эти же guarded entrypoints доступны через menu:

```bash
./scripts/project-menu.sh --run check-pam
./scripts/project-menu.sh --run enable-pam
./scripts/project-menu.sh --run disable-pam
```

Menu не вносит собственных PAM/authselect/GDM/sudo изменений и только
делегирует в `check-pam-state.sh`, `enable-pam.sh` или `disable-pam.sh`.

## Включение

```bash
./scripts/enable-pam.sh "$USER"
```

Если fingerprint уже был включён через `authselect with-fingerprint`, скрипт
только создаёт backup/snapshot и пишет, что изменений `authselect` не было.
Это важно для систем, где fingerprint был включён до проекта.

Если `with-fingerprint` отсутствует, скрипт выполняет только штатный путь:

```bash
sudo authselect enable-feature with-fingerprint
sudo authselect apply-changes
```

Перед изменением он:

- запускает `./scripts/check-dbus-chain.sh --wait 20`;
- запускает `fprintd-verify "$USER"`, если не указан `--assume-verified`;
- сохраняет `authselect current` и relevant PAM/authselect files в
  `/opt/fedora-validity/backups/pam-*`;
- создаёт project marker в `/opt/fedora-validity/state/` только если именно
  проект включил `with-fingerprint`.

`--assume-verified` использовать только после отдельного успешного
`fprintd-verify "$USER"`.

## Rollback

Обычный rollback:

```bash
./scripts/disable-pam.sh
```

Без project marker скрипт не отключает fingerprint, потому что feature могла
быть включена до проекта. Для намеренного глобального отключения:

```bash
./scripts/disable-pam.sh --force
```

Rollback меняет только `authselect with-fingerprint` через:

```bash
sudo authselect disable-feature with-fingerprint
sudo authselect apply-changes
```

Пароль должен оставаться fallback через штатную Fedora PAM-конфигурацию.

## Проверка sudo

В локальном интерактивном терминале:

```bash
sudo -k
sudo true
```

Ожидаемое поведение:

- верный зарегистрированный палец даёт успешную авторизацию;
- неверный палец не даёт успешную авторизацию;
- пароль остаётся fallback.

Если sudo prompt неудобно проходит через fingerprint, не закрывать текущую
root-сессию до проверки fallback. Для восстановления использовать:

```bash
./scripts/disable-pam.sh
```

## GNOME lock/unlock

Проверять только после успешного sudo/fallback теста.

1. Убедиться, что пароль известен и работает.
2. Заблокировать GNOME session.
3. Проверить unlock зарегистрированным пальцем.
4. Проверить, что неверный палец не разблокирует session.
5. Проверить пароль как fallback.

## GDM login

Проверять осторожно только после успешных sudo и lock screen тестов. Перед
logout/reboot должен быть готов rollback путь и рабочий пароль.

На конфигурации с включённым autologin обнаружен риск: после logout GDM может
запустить параллельные `gdm-fingerprint` и `gdm-password` conversations. В
журнале это выглядело как успешная PAM-аутентификация через `pam_fprintd`,
затем успешное открытие password session и ошибки GDM вида:

```text
Gdm: Couldn't find session for user
Gdm: Tried to look up non-existent conversation gdm-password
GdmSession: Tried to start session of nonexistent conversation gdm-password
```

После такого состояния вход мог зависнуть до reboot. Поэтому GDM fingerprint
login не считается production-ready критерием для этого проекта. Безопасная
граница текущей интеграции: `sudo`, GNOME lock/unlock и password fallback.

Если после logout GDM fingerprint ведёт себя нестабильно, войти паролем и
отключить project-enabled fingerprint:

```bash
./scripts/disable-pam.sh
```

Если fingerprint был включён до проекта, `disable-pam.sh` без marker не будет
его отключать. Тогда решение об `--force` принимать вручную.

## Polkit prompts

Polkit authentication prompts используют системный PAM путь Fedora. Если
`with-fingerprint` активен и конкретный prompt идёт через этот путь, fingerprint
может появиться там без отдельной настройки проекта. Это проверяется вручную
после sudo и lock screen. Проект не добавляет отдельные polkit policy changes
для PAM-аутентификации.

## Browser passkeys / WebAuthn

Этот проект не делает fingerprint sensor браузерным security key, passkey или
WebAuthn authenticator. Стек `python-validity` -> `open-fprintd` ->
`pam_fprintd.so` работает на уровне локального Linux PAM/fprintd и не
предоставляет браузеру FIDO2/WebAuthn authenticator для GitHub, passkeys или
двухфакторной аутентификации сайтов.

## Критерии успеха этапа

1. `./scripts/check-dbus-chain.sh --wait 20` проходит.
2. `./scripts/stability-check.sh --verify "$USER"` проходит.
3. `sudo -k && sudo true` предлагает fingerprint или корректный fallback.
4. Неверный палец не даёт успешную авторизацию.
5. Пароль остаётся fallback.
6. GNOME lock screen проверен вручную.
7. GDM login не является production-ready критерием на autologin setup.
8. Есть rollback через `scripts/disable-pam.sh`.
