# fedora-validity-setup

Воспроизводимый локальный setup для Validity Sensors `138a:0097` на Fedora Workstation 44 с Python 3.14.

Проект собирает `open-fprintd` и `python-validity` из upstream-исходников в изолированный prefix `/opt/fedora-validity`, устанавливает минимальные D-Bus/systemd артефакты через `scripts/*.sh` и даёт проверяемые install/test/rollback flows.

## Поддерживается

- Fedora Workstation 44 GNOME.
- Python 3.14 из Fedora RPM.
- USB fingerprint sensor Validity Sensors `138a:0097`.
- Локальная сборка upstream `uunicorn/python-validity` и `uunicorn/open-fprintd`.

## Не поддерживается

- Проект не удаляет штатные `fprintd`, `fprintd-pam`, `libfprint`.
- Не используются старые COPR RPM `python-validity` / `open-fprintd`, `--skip-broken`, `--nodeps`, downgrade или замена системного Python.
- Проект не обещает GitHub/passkeys/WebAuthn через fingerprint. Это отдельная
  тема.

Если `authselect current` уже содержит `with-fingerprint`, это существующее состояние системы, а не действие этого проекта.

## Быстрый путь

```bash
./scripts/clean-old-copr.sh
./scripts/install-deps.sh
./scripts/fetch-upstream.sh
./scripts/prepare-venv.sh
./scripts/build-open-fprintd.sh
./scripts/build-python-validity.sh
./scripts/prepare-firmware.sh
./scripts/install-dbus-policy.sh
```

Foreground debug flow в двух терминалах:

```bash
# Terminal 1
./scripts/run-open-fprintd-debug.sh --stop-stock-fprintd

# Terminal 2
./scripts/run-python-validity-debug.sh --auto-devpath
```

Проверка клиентского пути:

```bash
./scripts/check-dbus-chain.sh
./scripts/enroll-test.sh --list-only
./scripts/stability-check.sh --iterations 3
./scripts/enroll-test.sh --finger right-index-finger "$USER"
```

## Script menu

Для повторяемых ручных проверок можно использовать тонкий dispatcher:

```bash
./scripts/project-menu.sh
```

Тот же menu можно запускать неинтерактивно:

```bash
./scripts/project-menu.sh --run check-dbus
./scripts/project-menu.sh --run stability
./scripts/project-menu.sh --run systemd-test
./scripts/project-menu.sh --run enroll
./scripts/project-menu.sh --run check-pam
```

`project-menu.sh` не редактирует PAM, GDM, sudo, systemd или D-Bus files
напрямую. Все действия делегируются существующим guarded scripts.

## Systemd flow

После успешного foreground flow:

```bash
./scripts/install-systemd.sh
./scripts/systemd-test.sh --verify "$USER"
```

`install-systemd.sh` также устанавливает `system-sleep` hook, который после
resume перезапускает project services и сбрасывает stale USB handle.

Автозапуск включать только после ручной systemd-проверки:

```bash
./scripts/prepare-firmware.sh
./scripts/install-systemd.sh --enable
sudo systemctl restart open-fprintd.service python3-validity.service
./scripts/systemd-test.sh --verify "$USER"
```

После reboot проверить:

```bash
./scripts/check-dbus-chain.sh
./scripts/stability-check.sh --verify "$USER"
fprintd-list "$USER"
fprintd-verify "$USER"
```

## PAM/sudo/GNOME integration

PAM/authselect integration является отдельным guarded этапом после зелёного
service layer. Сначала выполнить read-only snapshot:

```bash
./scripts/check-pam-state.sh
./scripts/check-pam-state.sh --verify "$USER"
```

Включение через штатный Fedora authselect путь:

```bash
./scripts/enable-pam.sh "$USER"
```

Если `with-fingerprint` уже включён, скрипт не делает лишних authselect
изменений. Если feature отсутствует, он создаёт backup и выполняет:

```bash
sudo authselect enable-feature with-fingerprint
sudo authselect apply-changes
```

Rollback:

```bash
./scripts/disable-pam.sh
```

`disable-pam.sh` без `--force` отключает fingerprint только если проект сам
включил `with-fingerprint` и оставил project marker. Подробности:
[PAM, sudo, GNOME и GDM](docs/pam-gdm-sudo.md).

## Rollback

Полный rollback project systemd/D-Bus/helper артефактов:

```bash
./scripts/rollback.sh
```

Чистая переустановка только systemd unit-файлов:

```bash
./scripts/clean-systemd-install.sh
./scripts/install-systemd.sh
```

## Документация

- [Install flow](docs/install.md)
- [Rollback flow](docs/rollback.md)
- [Systemd design](docs/systemd-design.md)
- [PAM, sudo, GNOME и GDM](docs/pam-gdm-sudo.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Security and privacy](docs/security-and-privacy.md)
- [Release checklist](docs/release-checklist.md)
- [Fedora 44 / Python 3.14 notes](docs/fedora44-python314-notes.md)
