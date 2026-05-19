# Troubleshooting

Этот проект не включает PAM/GDM/sudo fingerprint authentication. Не менять
`authselect`, `/etc/pam.d`, GDM или sudo policy в рамках publication flow.

## python-validity exits after sensor reboot

During first initialization `python-validity` may reboot the USB sensor and exit
normally. In the journal this looks like:

```text
Initialization ended up in rebooting the sensor. Normal exit.
usb 1-9: USB disconnect, device number 6
usb 1-9: new full-speed USB device number 8
```

In that state `open-fprintd` keeps running, but `fprintd-list "$USER"` returns
`No devices available` because the backend process is gone and no device is
registered.

Use:

```bash
./scripts/run-python-validity-debug.sh --auto-devpath
```

The script retries once by default after a normal backend exit and refreshes the
USB `--devpath`. To change this:

```bash
./scripts/run-python-validity-debug.sh --auto-devpath --reboot-retries 2
```

## Missing firmware file

If `python-validity` exits with:

```text
FileNotFoundError: ... /var/run/python-validity//6_07f_lenovo_mis_qm.xpfwext
```

prepare the runtime firmware file through the project script. This must be
re-run after reboot because `/var/run` is a runtime tmpfs:

```bash
./scripts/prepare-firmware.sh
```

This creates `/var/run/python-validity` and runs
`/opt/fedora-validity/venv/bin/validity-sensors-firmware` via `sudo`.

## AccessDenied from fprintd-list

If `fprintd-list "$USER"` finds a device but then fails with:

```text
ListEnrolledFingers failed: GDBus.Error:org.freedesktop.DBus.Error.AccessDenied:
Sender is not authorized to send message
```

install the backend D-Bus policy:

```bash
./scripts/install-dbus-policy.sh
```

Then stop and restart both foreground debug services. The likely missing policy
is `io.github.uunicorn.Fprint.conf`; it authorizes root-owned `open-fprintd` to
call the `python-validity` backend interface.

## UnknownMethod: RegisterDevice

If `python-validity` logs:

```text
org.freedesktop.DBus.Error.UnknownMethod: Метод “RegisterDevice” не существует
```

then the current owner of `net.reactivated.Fprint` is probably stock Fedora
`fprintd`, not `open-fprintd`. Stock `fprintd` exposes the normal client API but
does not expose the backend registration method.

Restart the first terminal with:

```bash
./scripts/run-open-fprintd-debug.sh --stop-stock-fprintd
```

Then start the backend again:

```bash
./scripts/run-python-validity-debug.sh --auto-devpath
```

## systemd install останавливается на sudo/fingerprint authentication

Если `scripts/install-systemd.sh` запущен из неинтерактивной API-сессии, sudo
может попытаться выполнить fingerprint authentication и уйти в timeout:

```text
Place your finger on the fingerprint reader
Verification timed out
```

Запустить команды нужно из обычного локального терминала, где можно пройти
sudo prompt:

```bash
./scripts/install-systemd.sh
./scripts/systemd-test.sh --verify "$USER"
```

Install-скрипт не включает сервисы по умолчанию. Он только устанавливает
unit-файлы, устанавливает D-Bus policy через `scripts/install-dbus-policy.sh` и
выполняет `systemctl daemon-reload`.

## python3-validity.service: Job canceled

Если `scripts/systemd-test.sh --verify "$USER"` заканчивается строкой:

```text
Job for python3-validity.service canceled.
```

проверить журнал:

```bash
journalctl -u open-fprintd.service -u python3-validity.service -u fprintd.service -n 120 --no-pager
```

Найденный в iteration 004 вариант причины: readiness-check через
`busctl introspect net.reactivated.Fprint` активировал stock `fprintd.service`
до того, как `open-fprintd.service` успевал стать owner D-Bus name. Stock
`fprintd.service` конфликтовал с `open-fprintd.service`, systemd останавливал
`open-fprintd.service`, а запуск `python3-validity.service` отменялся.

Исправленная версия `systemd/python3-validity.service` ждёт owner через
`busctl --system list` и проверяет unit `open-fprintd.service`, не вызывая
D-Bus activation. После обновления repo-файла нужно переустановить unit:

```bash
./scripts/install-systemd.sh
./scripts/systemd-test.sh --verify "$USER"
```

## systemd services active, but fprintd-list says No devices available

Если оба project services уже `active (running)`, но первый `fprintd-list`
сразу после старта пишет:

```text
No devices available
```

проверить регистрацию device:

```bash
busctl --system call net.reactivated.Fprint /net/reactivated/Fprint/Manager net.reactivated.Fprint.Manager GetDevices
```

Если через пару секунд команда возвращает:

```text
ao 1 "/net/reactivated/Fprint/Device/0"
```

это была гонка тестового скрипта: `python3-validity.service` уже считался
active, но backend ещё не успел выполнить `RegisterDevice`. Исправленный
`scripts/systemd-test.sh` ждёт `GetDevices` перед `fprintd-list`.

## enabled services после reboot: No devices available

Если после `scripts/install-systemd.sh --enable` и reboot:

```bash
fprintd-list "$USER"
fprintd-verify "$USER"
```

возвращают:

```text
No devices available
Impossible to verify: GDBus.Error:net.reactivated.Fprint.Error.NoSuchDevice:
```

проверить:

```bash
systemctl status python3-validity.service --no-pager -l
journalctl -b -u python3-validity.service --no-pager
```

Найденная причина: `validity-sensors-firmware` запускался на раннем boot,
когда DNS/network ещё не был готов:

```text
urllib.error.URLError: <urlopen error [Errno -3] Temporary failure in name resolution>
```

Исправление: использовать cache-first helper:

```bash
./scripts/prepare-firmware.sh
./scripts/install-systemd.sh --enable
sudo systemctl restart open-fprintd.service python3-validity.service
./scripts/systemd-test.sh --verify "$USER"
```

После этого выполнить reboot-test. Firmware cache хранится в
`/opt/fedora-validity/firmware/python-validity`, а runtime copy создаётся в
`/var/run/python-validity`.

## systemd-test видит project services как foreground processes

Если `scripts/systemd-test.sh --verify "$USER"` пишет:

```text
foreground open-fprintd/python-validity process appears to be running
```

и показанные PID совпадают с `MainPID` в `systemctl status open-fprintd.service
python3-validity.service`, это не foreground debug flow, а уже запущенные
systemd services. Исправленный `scripts/systemd-test.sh` сравнивает найденные
PID с `MainPID` project services и игнорирует их.

Для чистой переустановки только systemd unit-файлов:

```bash
./scripts/clean-systemd-install.sh
./scripts/install-systemd.sh
./scripts/systemd-test.sh --verify "$USER"
```

`clean-systemd-install.sh` не удаляет D-Bus policy и не меняет
PAM/authselect/GDM/sudo. Для полного удаления project systemd unit-файлов и
backend D-Bus policy использовать:

```bash
./scripts/rollback.sh
```

Если старый вариант `clean-systemd-install.sh` или `systemd-test.sh` печатал:

```text
Failed to reset failed state of unit open-fprintd.service: Unit open-fprintd.service not loaded.
Failed to reset failed state of unit python3-validity.service: Unit python3-validity.service not loaded.
```

это был шум от `systemctl reset-failed open-fprintd.service
python3-validity.service`. На Fedora эта команда может вернуть `Unit ... not
loaded`, даже если unit-файлы установлены и `systemctl status` показывает
`Loaded: loaded`. Исправленные скрипты больше не вызывают `reset-failed` для
этих unit-файлов.

If the system becomes difficult to authenticate into after later stages, boot
with an alternate recovery method and disable the authselect fingerprint
feature:

```bash
sudo authselect disable-feature with-fingerprint
sudo authselect apply-changes
```
