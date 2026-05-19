# Systemd design

Этот документ фиксирует текущий systemd/D-Bus дизайн проекта. Он не описывает
PAM/GDM/sudo integration и не требует менять `authselect`.

## Цель

После успешного foreground debug flow запустить тот же стек через systemd:

```text
USB 138a:0097
-> python-validity backend
-> open-fprintd compatibility service
-> net.reactivated.Fprint D-Bus API
-> fprintd-list / fprintd-enroll / fprintd-verify
```

## Unit-файлы

- `systemd/open-fprintd.service`
  - запускает `/opt/fedora-validity/venv/lib/open-fprintd/open-fprintd --debug`;
  - использует `Type=simple`, чтобы не конфликтовать с stock `fprintd.service`,
    который уже объявляет `BusName=net.reactivated.Fprint`;
  - объявляет `Conflicts=fprintd.service`, но не удаляет и не disable-ит stock
    service.
- `systemd/python3-validity.service`
  - требует `open-fprintd.service`;
  - перед запуском ждёт, пока `net.reactivated.Fprint` будет принадлежать
    именно `open-fprintd.service`;
  - готовит config directory и вызывает cache-first firmware helper;
  - использует `Restart=on-success`, потому что backend может штатно завершиться
    после reboot сенсора.

## Firmware

`/var/run/python-validity` является runtime tmpfs и очищается после reboot.
Поэтому `python3-validity.service` вызывает:

```text
/opt/fedora-validity/bin/ensure-firmware.sh
```

Helper сначала копирует `.xpfwext` из persistent cache:

```text
/opt/fedora-validity/firmware/python-validity
```

Если cache пустой, helper запускает upstream `validity-sensors-firmware` и затем
заполняет cache. Сам firmware binary не хранится в репозитории.

## D-Bus policy

Для client-facing API используется системная policy `net.reactivated.Fprint`.
Для backend call path нужен project-installed файл:

```text
/etc/dbus-1/system.d/io.github.uunicorn.Fprint.conf
```

Он разрешает root-owned `open-fprintd` вызывать backend interface
`io.github.uunicorn.Fprint.Device`. Установка выполняется только через:

```bash
./scripts/install-dbus-policy.sh
```

## Проверка

Безопасная read-only диагностика текущей цепочки:

```bash
./scripts/check-dbus-chain.sh
./scripts/stability-check.sh --iterations 3
```

Ручной systemd test flow:

```bash
./scripts/systemd-test.sh --verify "$USER"
```

`systemd-test.sh` останавливает `python3-validity.service`, затем
`open-fprintd.service`, затем stock `fprintd.service`, после чего заново
стартует `open-fprintd.service` и `python3-validity.service`. Это важно для
сброса stale USB handle в backend-процессе. Скрипт делает это только как явный
test workflow, не
включает автозапуск и не меняет PAM/authselect/GDM/sudo.

## Stability matrix

До PAM/GDM/sudo integration сервисный слой должен пройти такие проверки:

```bash
# Baseline without changing system state
./scripts/stability-check.sh --iterations 3

# Physical verify, explicitly requested
./scripts/stability-check.sh --verify "$USER"

# Project service restart path
./scripts/systemd-test.sh --verify "$USER"
./scripts/stability-check.sh --iterations 2 --verify "$USER"

# After reboot
./scripts/stability-check.sh --iterations 2 --verify "$USER"

# After suspend/resume
./scripts/stability-check.sh --iterations 2 --verify "$USER"
```

Если после reboot или suspend/resume появляется `USBError: No such device`,
сначала выполнить:

```bash
./scripts/systemd-test.sh --verify "$USER"
```

Если restart workflow чинит состояние, следующий production-шаг — отдельная
restart/rebind strategy. Если не чинит, нужно исследовать startup path
`python-validity` после USB re-enumeration.

Если sensor кратко исчезает из `lsusb` сразу после verify, использовать:

```bash
./scripts/check-dbus-chain.sh --wait 15
./scripts/stability-check.sh --iterations 2 --sleep 8 "$USER"
```

`check-dbus-chain.sh` по умолчанию ждёт до 10 секунд; `--wait 15` полезен для
ручной проверки transient USB re-enumeration.

## Rollback

Полный rollback project-installed systemd/D-Bus/helper артефактов:

```bash
./scripts/rollback.sh
```

Rollback не отключает `authselect with-fingerprint`, не редактирует
`/etc/pam.d`, не меняет GDM/sudo и не удаляет Fedora RPM `fprintd`,
`fprintd-pam`, `libfprint`.

## Suspend/Resume

После suspend/resume USB sensor может вернуться с новым device number, например
`Bus 001 Device 006` -> `Bus 001 Device 010`. При этом `python-validity.service`
может остаться старым процессом и держать stale USB handle. Симптом:

```text
usb.core.USBError: [Errno 19] No such device
```

Для этого `install-systemd.sh` устанавливает:

```text
/opt/fedora-validity/bin/restart-project-services.sh
/usr/lib/systemd/system-sleep/fedora-validity-setup
```

`system-sleep` hook:

- ничего не делает на `pre`;
- на `post` вызывает `restart-project-services.sh --no-status`;
- restart order:
  - stop `python3-validity.service`;
  - stop `open-fprintd.service`;
  - stop stock `fprintd.service`;
  - start `open-fprintd.service`;
  - start `python3-validity.service`.

Ручной эквивалент:

```bash
./scripts/restart-project-services.sh
./scripts/check-dbus-chain.sh --wait 20
```
