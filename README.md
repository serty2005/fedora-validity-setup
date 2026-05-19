# fedora-validity-setup

Воспроизводимый локальный setup для Validity Sensors `138a:0097` на Fedora Workstation 44 с Python 3.14.

Проект собирает `open-fprintd` и `python-validity` из upstream-исходников в изолированный prefix `/opt/fedora-validity`, устанавливает минимальные D-Bus/systemd артефакты через `scripts/*.sh` и даёт проверяемые install/test/rollback flows.

## Поддерживается

- Fedora Workstation 44 GNOME.
- Python 3.14 из Fedora RPM.
- USB fingerprint sensor Validity Sensors `138a:0097`.
- Локальная сборка upstream `uunicorn/python-validity` и `uunicorn/open-fprintd`.

## Не поддерживается в этом этапе

- Проект не включает PAM/GDM/sudo fingerprint authentication.
- Проект не меняет `authselect`, `/etc/pam.d`, GDM или sudo policy.
- Проект не удаляет штатные `fprintd`, `fprintd-pam`, `libfprint`.
- Не используются старые COPR RPM `python-validity` / `open-fprintd`, `--skip-broken`, `--nodeps`, downgrade или замена системного Python.

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
- [Troubleshooting](docs/troubleshooting.md)
- [Security and privacy](docs/security-and-privacy.md)
- [Release checklist](docs/release-checklist.md)
- [Fedora 44 / Python 3.14 notes](docs/fedora44-python314-notes.md)
