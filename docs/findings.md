# Findings

Diagnostic log: local generated diagnostics file, intentionally not published.

Latest local state check: 2026-05-18 during iteration 003.

## System

- Fedora: `Fedora release 44 (Forty Four)`.
- Kernel: `Linux fedora 7.0.8-200.fc44.x86_64`.
- Python: `Python 3.14.4`.
- Python RPM: `python3-3.14.4-2.fc44.x86_64`.
- Current Python ABI target for local builds: `cp314` / Python 3.14.
- SELinux: `Enforcing`.

## Fingerprint Sensor

- USB sensor is present:
  - `Bus 001 Device 006: ID 138a:0097 Validity Sensors, Inc.`
  - serial: redacted from publishable documentation.
  - `bcdDevice 1.64`
  - vendor-specific USB class with bulk and interrupt endpoints.
- Automatic USB path detection now reports:
  - bus: `001`
  - device: `006`
  - node: `/dev/bus/usb/001/006`
- Current USB device node permissions are `crw-rw-r--. 1 root root` for `/dev/bus/usb/001/006`, so an unprivileged foreground process is unlikely to have raw write access without a udev rule, group change, or root/system service.
- `udevadm info` confirms `PRODUCT=138a/97/164` and `ID_USB_INTERFACES=:ff0000:`; device serial is intentionally redacted from publishable documentation.
- `lsusb -d 138a:0097 -v` reported `Couldn't open device, some information will be missing`, so later stages may need a udev rule or a root/system service to access the raw USB device.
- Kernel `dmesg` and privileged `lsusb -v` details were not available in this run because `--with-sudo` requested the user's password and it was not entered through this session.

## Standard fprintd State

- Installed Fedora packages:
  - `libfprint-1.94.10-1.fc44.x86_64`
  - `fprintd-1.94.5-5.fc44.x86_64`
  - `fprintd-pam-1.94.5-5.fc44.x86_64`
- Standard `fprintd.service` exists and is static.
- `fprintd-list "$USER"` returns `No devices available`.
- D-Bus currently shows the standard service when activated:
  - `net.reactivated.Fprint`
  - owned by `fprintd.service`
- Conclusion: the sensor is visible on USB, but stock Fedora 44 `libfprint/fprintd` does not expose it as a usable fingerprint device.

## Foreground open-fprintd/python-validity State

- Foreground chain reached list-only success:
  - `open-fprintd` owns `net.reactivated.Fprint`.
  - `python-validity` registered one backend device.
  - `fprintd-list "$USER"` sees `/net/reactivated/Fprint/Device/0`.
  - Current user has enrolled `right-index-finger`.
- `GetDevices` returns `ao 1 "/net/reactivated/Fprint/Device/0"`.
- `fprintd-enroll "$USER"` completed.
- `fprintd-verify "$USER"` returned `verify-match (done)`.

## Conflicts And Risky Existing State

- Enabled repositories no longer include stale `python-validity/python-validitya` COPR repositories.
- Previous diagnostic logs still contain old `taaem/python-validity` entries; treat those as historical state before cleanup.
- `authselect current` already includes `with-fingerprint`.
- PAM files already reference `pam_fprintd.so`:
  - `/etc/pam.d/system-auth`
  - `/etc/pam.d/fingerprint-auth`
  - `/etc/authselect/system-auth`
  - `/etc/authselect/fingerprint-auth`
- This project did not enable PAM. Because `fprintd-verify` is not successful yet, the current PAM fingerprint feature is an existing risk and should be treated carefully. Do not make further PAM changes until verification works.
- No project-created `python3-validity.service` or `open-fprintd.service` exists yet.

## Components To Build Locally

- `python-validity` from source, installed under `/opt/fedora-validity` or `/opt/fedora-validity/venv`.
- `open-fprintd` from source, installed under the same controlled prefix.
- Local systemd units:
  - `python3-validity.service`
  - `open-fprintd.service`
- A udev rule for `138a:0097` may be needed after foreground testing confirms the service user and access model.

## Known Risks

- Python 3.14 syntax/import compatibility is partly verified: `compileall` passes and `/opt/fedora-validity/venv` imports `usb`, `cryptography`, `yaml`, `dbus`, and `gi`.
- `dbus-python`, `pygobject`, and `systemd-python` are available through Fedora system packages exposed to the venv by `--system-site-packages`; do not replace them with global `sudo pip`.
- Standard `fprintd.service` owns `net.reactivated.Fprint` when activated; `open-fprintd` may conflict with it unless the standard service is stopped during foreground testing.
- `python-validity` needs firmware extension files under `/var/run/python-validity`; use `scripts/prepare-firmware.sh` instead of manual commands.
- Foreground testing also needs the backend D-Bus policy `io.github.uunicorn.Fprint.conf` installed into `/etc/dbus-1/system.d`; use `scripts/install-dbus-policy.sh`.
- SELinux is enforcing. AVC details need a sudo-authenticated diagnostic run if services later fail to access USB, D-Bus, or filesystem paths.
- PAM fingerprint integration is already enabled before a successful verify. Rollback must avoid disabling it unless this project explicitly changes it in a later stage.

## Iteration 004: состояние systemd/udev

- Repo-local systemd unit-файлы созданы:
  - `systemd/open-fprintd.service`
  - `systemd/python3-validity.service`
- Repo-local udev rule создан:
  - `udev/99-validity-138a0097.rules`
- `scripts/install-systemd.sh` устанавливает unit-файлы и D-Bus policy, выполняет `systemctl daemon-reload` и не включает сервисы без явного `--enable`.
- `scripts/systemd-test.sh` запускает ручную проверку systemd path и выполняет `fprintd-list`; `fprintd-verify` запускается только с `--verify`.
- `scripts/rollback.sh` теперь удаляет project systemd unit-файлы и backend D-Bus policy, но всё ещё не меняет PAM/authselect/GDM/sudo.
- Фактическая systemd-установка из API-сессии не завершилась, потому что sudo/fingerprint authentication ушёл в timeout. Команды установки и проверки нужно запускать из интерактивного локального терминала.
- Первый интерактивный `systemd-test.sh --verify "$USER"` дошёл до `Job for python3-validity.service canceled`.
- Причина: readiness-check через `busctl introspect net.reactivated.Fprint` активировал stock `fprintd.service` до того, как `open-fprintd.service` успел стать owner D-Bus name. Stock `fprintd.service` затем остановил `open-fprintd.service` через unit conflict.
- Исправление: `systemd/python3-validity.service` теперь ждёт через `busctl --system list`, пока `net.reactivated.Fprint` будет принадлежать unit `open-fprintd.service`; это не активирует stock `fprintd`.
- Второй интерактивный `systemd-test.sh --verify "$USER"` успешно запустил оба сервиса, но первый `fprintd-list` сработал до `RegisterDevice` и показал `No devices available`.
- Свежая проверка после регистрации показала `GetDevices -> ao 1 "/net/reactivated/Fprint/Device/0"` и `fprintd-list "$USER"` увидел `right-index-finger`.
- Исправление: `scripts/systemd-test.sh` теперь ждёт ненулевой `GetDevices` перед `fprintd-list` и `fprintd-verify`.
- Повторный `systemd-test.sh --verify "$USER"` показал false positive в foreground check: уже запущенные project systemd services имеют те же command line, что и foreground debug flow.
- Исправление: `scripts/systemd-test.sh` теперь игнорирует PID, совпадающие с `MainPID` project systemd services.
- Для чистой переустановки только systemd unit-файлов создан `scripts/clean-systemd-install.sh`; он не удаляет D-Bus policy и не меняет PAM/authselect/GDM/sudo.
- Перед clean reinstall ручной `scripts/systemd-test.sh --verify "$USER"` успешно запросил палец, включил индикатор сенсора и завершил проверку после прикладывания пальца. Systemd path для verify считается подтверждённым.
- `scripts/clean-systemd-install.sh` и `scripts/systemd-test.sh` сначала печатали `Unit ... not loaded` при `reset-failed`. Проверка показала, что Fedora может возвращать это даже при установленных и `loaded` unit-файлах, поэтому `reset-failed` удалён из этих workflow.
- После clean reinstall повторный `scripts/systemd-test.sh --verify "$USER"` успешно дошёл до:
  - `GetDevices attempt 3/20: ao 1 "/net/reactivated/Fprint/Device/0"`;
  - `fprintd-list "$USER"` видит `right-index-finger`;
  - `fprintd-verify "$USER"` возвращает `verify-match (done)`.
- Текущее состояние после проверки: `open-fprintd.service` и `python3-validity.service` активны, но `disabled`; автозапуск ещё не включён.
- Reboot-test без очистки BIOS fingerprint-data успешен:
  - `GetDevices attempt 5/20: ao 1 "/net/reactivated/Fprint/Device/0"`;
  - `fprintd-list "$USER"` видит `right-index-finger`;
  - `fprintd-verify "$USER"` возвращает `verify-match (done)`.
- Проверки другими пальцами и плохим сканом показали корректные события и отсутствие ложного match.
- Текущее состояние после reboot-test: оба project services активны, но `disabled`; автозапуск ещё не включён.
- После `scripts/install-systemd.sh --enable` и reboot `python3-validity.service` не стартовал из-за `validity-sensors-firmware`: ранний boot не имел DNS/network, а firmware runtime file в `/var/run/python-validity` исчез после reboot.
- Исправление: добавлен `scripts/ensure-firmware.sh`, persistent cache `/opt/fedora-validity/firmware/python-validity`, установка helper в `/opt/fedora-validity/bin/ensure-firmware.sh`, и перевод `python3-validity.service` на cache-first helper.
- После `scripts/prepare-firmware.sh`, `scripts/install-systemd.sh --enable` и reboot enabled-services path успешно работает:
  - `open-fprintd.service`: `enabled`, `active`;
  - `python3-validity.service`: `enabled`, `active`;
  - `GetDevices`: `ao 1 "/net/reactivated/Fprint/Device/0"`;
  - `fprintd-list "$USER"` видит `right-index-finger`;
  - `fprintd-verify "$USER"` возвращает `verify-match (done)`.
- Firmware cache заполнен: `/opt/fedora-validity/firmware/python-validity/6_07f_lenovo_mis_qm.xpfwext`.

## Iteration 006: D-Bus chain check

- Репозиторий синхронизирован с `origin/main`; опубликованный commit:
  `93fdc89 Initial Fedora Validity setup publication`.
- `scripts/enroll-test.sh --list-only` уже корректно вызывает
  `fprintd-list "$TARGET_USER"` и не передаёт `--list-only` в `fprintd-list`.
- Добавлен read-only checker `scripts/check-dbus-chain.sh`.
- Текущая система больше не воспроизводит старый `AccessDenied`:
  - `net.reactivated.Fprint` принадлежит `open-fprintd.service`;
  - `fprintd.service` не активен;
  - `RegisterDevice` и `ListEnrolledFingers` видны через introspection;
  - `io.github.uunicorn.Fprint.conf` установлен в `/etc/dbus-1/system.d`;
  - `GetDevices` возвращает `ao 1 "/net/reactivated/Fprint/Device/0"`.
- Свежая ошибка `./scripts/check-dbus-chain.sh` и
  `./scripts/enroll-test.sh --list-only`:
  `usb.core.USBError: [Errno 19] No such device`.
- Вывод: D-Bus/policy слой пройден, но `python-validity` держит stale USB
  handle после того, как сенсор снова появился как `Bus 001 Device 010`.
- Безопасный следующий шаг из локального интерактивного терминала:
  `./scripts/systemd-test.sh --verify "$USER"`, чтобы перезапустить project
  services через документированный workflow и перепривязать backend к текущему
  USB device.
- После ручной проверки выяснилось, что старый `systemd-test.sh` делал
  `systemctl start` для уже активных project services, то есть не перезапускал
  `python-validity` и не сбрасывал stale USB handle.
- Исправление: `scripts/systemd-test.sh` теперь явно останавливает
  `python3-validity.service`, затем `open-fprintd.service`, затем stock
  `fprintd.service`, и только после этого стартует project services заново.
- Iteration 008 добавляет `scripts/stability-check.sh` для повторяемой
  read-only проверки service layer без enroll и без PAM/authselect/GDM/sudo.
- После `verify-no-match` пользователь поймал transient-состояние: `lsusb` на
  короткое время не видел `138a:0097`, затем сенсор вернулся как
  `Bus 001 Device 012`, а `python3-validity.service` получил новый PID.
- `scripts/check-dbus-chain.sh` теперь поддерживает `--wait SECONDS` и по
  умолчанию ждёт до 10 секунд появления USB device и registered D-Bus device.

## Ближайшие шаги

1. Выполнить `./scripts/stability-check.sh --iterations 3` из локального терминала.
2. Для post-verify transient окна использовать
   `./scripts/check-dbus-chain.sh --wait 15`.
3. Выполнить reboot и suspend/resume stability matrix.
3. Если stale USB handle повторяется после suspend/replug, добавить отдельную
   итерацию для restart/rebind strategy.
4. PAM/authselect/GDM/sudo всё ещё не менять до отдельной итерации.
