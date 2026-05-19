# Rollback flow

Rollback удаляет project systemd/D-Bus/helper артефакты и не меняет PAM/authselect/GDM/sudo.

## Посмотреть действия без изменений

```bash
./scripts/rollback.sh --dry-run
```

## Выполнить rollback

```bash
./scripts/rollback.sh
```

Скрипт:

- останавливает `open-fprintd.service` и `python3-validity.service`;
- отключает эти services;
- удаляет `/etc/systemd/system/open-fprintd.service`;
- удаляет `/etc/systemd/system/python3-validity.service`;
- удаляет `/etc/dbus-1/system.d/io.github.uunicorn.Fprint.conf`;
- удаляет `/opt/fedora-validity/bin/ensure-firmware.sh`;
- удаляет `/opt/fedora-validity/bin/restart-project-services.sh`;
- удаляет `/usr/lib/systemd/system-sleep/fedora-validity-setup`;
- выполняет `systemctl daemon-reload`;
- пытается перезагрузить D-Bus policy.

`net.reactivated.Fprint.conf` не удаляется автоматически, если уже существует в системе: этот файл может принадлежать stock пакету или другой установке.

## Чистая переустановка systemd unit-файлов

Если нужно переустановить только project unit-файлы и оставить D-Bus policy:

```bash
./scripts/clean-systemd-install.sh
./scripts/install-systemd.sh
./scripts/systemd-test.sh --verify "$USER"
```

## Что rollback не делает

- Не отключает `authselect with-fingerprint`.
- Не редактирует `/etc/pam.d`.
- Не меняет GDM или sudo authentication policy.
- Не удаляет штатные Fedora RPM `fprintd`, `fprintd-pam`, `libfprint`.
- Не удаляет `/opt/fedora-validity/venv`, firmware cache и backups: они нужны для диагностики и повторной установки. Удалять весь prefix следует только вручную после отдельного решения.
