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

## Rollback

Полный rollback project-installed systemd/D-Bus/helper артефактов:

```bash
./scripts/rollback.sh
```

Rollback не отключает `authselect with-fingerprint`, не редактирует
`/etc/pam.d`, не меняет GDM/sudo и не удаляет Fedora RPM `fprintd`,
`fprintd-pam`, `libfprint`.
