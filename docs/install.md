# Install flow

Этот документ описывает публикационный путь установки для Fedora Workstation 44 / Python 3.14 / Validity Sensors `138a:0097`.

## Границы

- Все системные изменения выполняются только через `scripts/*.sh`.
- PAM/GDM/sudo integration не выполняется.
- `authselect` и `/etc/pam.d` не меняются.
- Штатные `fprintd`, `fprintd-pam`, `libfprint` не удаляются.
- Старые COPR RPM `python-validity` и `open-fprintd` не используются.

## Подготовка

```bash
./scripts/clean-old-copr.sh
./scripts/install-deps.sh
./scripts/fetch-upstream.sh
./scripts/prepare-venv.sh
```

`scripts/fetch-upstream.sh` клонирует upstream в локальный `third_party/` и обновляет `docs/upstream-commits.md`. Каталог `third_party/` не предназначен для публикации в GitHub-репозитории.

## Сборка

```bash
./scripts/build-open-fprintd.sh
./scripts/build-python-validity.sh
```

Обе сборки устанавливаются в `/opt/fedora-validity/venv`; глобальный `sudo pip` не используется.

## Firmware

```bash
./scripts/prepare-firmware.sh
```

Скрипт вызывает cache-first helper `scripts/ensure-firmware.sh`: сначала использует persistent cache `/opt/fedora-validity/firmware/python-validity`, затем при необходимости запускает upstream `validity-sensors-firmware` и заполняет cache. Это нужно для reboot/autostart, потому что `/var/run/python-validity` очищается при перезагрузке.

## D-Bus policy

```bash
./scripts/install-dbus-policy.sh
```

Скрипт устанавливает backend policy `io.github.uunicorn.Fprint.conf` и устанавливает `net.reactivated.Fprint.conf` только если системной policy ещё нет. Перед заменой существующих файлов создаётся backup в `/opt/fedora-validity/backups`.

## Foreground debug flow

Запустить в двух терминалах:

```bash
./scripts/run-open-fprintd-debug.sh --stop-stock-fprintd
```

```bash
./scripts/run-python-validity-debug.sh --auto-devpath
```

Затем проверить клиентскую сторону:

```bash
./scripts/enroll-test.sh --list-only
./scripts/enroll-test.sh "$USER"
```

## Systemd install/test

Установить unit-файлы без автозапуска:

```bash
./scripts/install-systemd.sh
```

Проверить systemd path:

```bash
./scripts/systemd-test.sh --verify "$USER"
```

`scripts/systemd-test.sh` останавливает stock `fprintd.service` только для теста, стартует project services, ждёт `GetDevices`, затем запускает `fprintd-list` и, при `--verify`, `fprintd-verify`.

## Enable after verification

Только после успешного foreground flow и `systemd-test.sh --verify`:

```bash
./scripts/prepare-firmware.sh
./scripts/install-systemd.sh --enable
sudo systemctl restart open-fprintd.service python3-validity.service
./scripts/systemd-test.sh --verify "$USER"
```

После reboot:

```bash
systemctl is-enabled open-fprintd.service python3-validity.service
systemctl is-active open-fprintd.service python3-validity.service
fprintd-list "$USER"
fprintd-verify "$USER"
```
