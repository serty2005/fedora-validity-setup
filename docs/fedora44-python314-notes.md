# Fedora 44 / Python 3.14 notes

Дата анализа: 2026-05-18

## Upstream revisions

- `python-validity`: `a6bbc21dce7b8b3c3cd92378a0b2579a2fb45920`
- `open-fprintd`: `b7073730bccca36e84484e3fcb4f8253ea038d07`

## Проверки без установки

- `python3 -m compileall -q` для Python-модулей, `dbus_service`, `bin` и `scripts` в обоих upstream прошёл без синтаксических ошибок на Python 3.14.4.
- Сгенерированные `__pycache__` после проверки удалены из `third_party/`.
- `rg` не нашёл `distutils`, `inspect.getargspec`, `inspect.formatargspec`, `collections.Mapping`, `collections.MutableMapping` или `from collections import ...`, которые часто ломаются на новых Python.

## python-validity

### Как запускается

- Основной foreground/debug запуск из README:
  - `PYTHONPATH=. ./dbus_service/dbus-service`
- Upstream systemd unit:
  - `third_party/python-validity/debian/python3-validity.service`
  - `ExecStart=/usr/lib/python-validity/dbus-service --debug`
  - `After=open-fprintd.service`
- Сервис регистрирует backend-устройство в `open-fprintd` через `RegisterDevice`.
- Поддерживается `--devpath usb-<busnum>-<address>`, что полезно для `138a:0097`, найденного как `/dev/bus/usb/001/006`.

### Python-зависимости

- Из `setup.py`:
  - `cryptography >= 2.1.4`
  - `pyusb >= 1.0.0`
  - `pyyaml >= 3.12`
- Из импортов runtime:
  - `dbus`
  - `dbus.mainloop.glib`
  - `gi.repository.GLib`
  - `usb`
  - `yaml`
  - `cryptography`
- Debian packaging дополнительно требует:
  - `python3-dbus`
  - `python3-usb`
  - `python3-yaml`
  - `dbus`
  - `open-fprintd >= 0.6`
  - `innoextract >= 1.6` для firmware workflow

### D-Bus

- Backend interface: `io.github.uunicorn.Fprint.Device`.
- Object path: `/io/github/uunicorn/Fprint/Device`.
- D-Bus policy file: `dbus_service/io.github.uunicorn.Fprint.conf`.
- `python-validity` waits for and talks to manager service `net.reactivated.Fprint` at `/net/reactivated/Fprint/Manager`.

### Файлы установки upstream

- D-Bus policy: `share/dbus-1/system.d/io.github.uunicorn.Fprint.conf`.
- Backend executable: `lib/python-validity/dbus-service`.
- Playground scripts: `share/python-validity/playground/`.
- systemd unit в Debian/RPM packaging: `python3-validity.service`.
- udev rule upstream поддерживает `138a:0097`, но только запускает/останавливает сервис и выставляет `ATTR{power/control}="auto"`; права на `/dev/bus/usb/...` явно не расширяет.

### Риски на Fedora 44 / Python 3.14

- `dbus-python` и `PyGObject` лучше брать из Fedora RPM (`python3-dbus`, `python3-gobject`), потому что сборка из PyPI внутри venv может потребовать системные headers и не всегда гладко проходит на свежем Python.
- Upstream пути `/usr/lib/python-validity` и `/etc/python-validity` нужно адаптировать под `/opt/fedora-validity` и локальные unit-файлы.
- В `EnrollStart` есть латентный баг в редком error path: используется `winbio_name`, но переменная не определена. Это не блокирует обычный путь с валидным finger name, но стоит исправить патчем перед production-use.
- Для доступа к `/dev/bus/usb/001/006` текущие права `root:root 0664`; foreground запуск от обычного пользователя, скорее всего, не сможет писать в устройство без udev/system service.

## open-fprintd

### Как запускается

- Основной executable:
  - `third_party/open-fprintd/dbus_service/open-fprintd`
- Upstream systemd unit:
  - `third_party/open-fprintd/debian/open-fprintd.service`
  - `Type=dbus`
  - `BusName=net.reactivated.Fprint`
  - `ExecStart=/usr/lib/open-fprintd/open-fprintd --debug`
- D-Bus activation file:
  - `dbus_service/net.reactivated.Fprint.service`
  - `Exec=/usr/lib/open-fprintd/open-fprintd --debug`
  - `SystemdService=open-fprintd.service`

### Python-зависимости

- `setup.py` не задаёт `install_requires`.
- Runtime imports:
  - `dbus`
  - `dbus.mainloop.glib`
  - `dbus.service`
  - `gi.repository.GObject`
  - `gi.repository.GLib`
- Debian packaging требует:
  - `python3-dbus`
  - `dbus`

### D-Bus

- Client-facing service name: `net.reactivated.Fprint`.
- Manager interface: `net.reactivated.Fprint.Manager`.
- Manager object path: `/net/reactivated/Fprint/Manager`.
- Device interface: `net.reactivated.Fprint.Device`.
- Device paths: `/net/reactivated/Fprint/Device/<n>`.
- Backend interface expected from drivers: `io.github.uunicorn.Fprint.Device`.

### Файлы установки upstream

- D-Bus activation: `share/dbus-1/system-services/net.reactivated.Fprint.service`.
- D-Bus policy: `share/dbus-1/system.d/net.reactivated.Fprint.conf`.
- Executable/scripts: `lib/open-fprintd/open-fprintd`, `suspend.py`, `resume.py`.
- Optional suspend/resume units:
  - `open-fprintd-suspend.service`
  - `open-fprintd-resume.service`

### Риски на Fedora 44 / Python 3.14

- Upstream использует `from gi.repository import GObject` и `GObject.MainLoop().run()`. На новых PyGObject предпочтительнее `GLib.MainLoop()`. Если runtime выдаст ошибку или deprecation breakage, минимальный patch должен заменить это на `from gi.repository import GLib` и `GLib.MainLoop().run()`.
- В `Manager.GetDevices()` возвращается `self.devices.values()`. В Python 3 это `dict_values`, а D-Bus marshalling надёжнее получает `list(self.devices.values())`. Если `fprintd-list` увидит ошибку типа marshalling/signature, это первый кандидат на patch.
- Debian package объявляет `Conflicts/Replaces: fprintd`. На Fedora стандартные `fprintd`, `fprintd-pam`, `libfprint` удалять нельзя без отдельного решения и rollback-плана, поэтому конфликт нужно решать локальным D-Bus/systemd переключением только после foreground-проверки.

## Нужно ли останавливать штатный fprintd

Да, для тестов `open-fprintd` должен владеть тем же system bus name: `net.reactivated.Fprint`. Сейчас этот name активирует штатный Fedora `fprintd.service`.

В этой итерации ничего не останавливалось и не переключалось. Для следующего этапа нужен отдельный debug/run-скрипт с явными командами, логом и rollback:

- проверить, не активен ли `fprintd.service`;
- временно остановить штатный `fprintd` только на время foreground-теста;
- запустить `open-fprintd` из checkout или `/opt/fedora-validity`;
- запустить `python-validity` и убедиться, что backend зарегистрировался;
- только после этого переходить к systemd/D-Bus activation.

## Upstream enroll/verify команды

- README upstream рекомендует:
  - `fprintd-enroll`
  - при проблемах смотреть `sudo systemctl status python3-validity`
  - после firmware/factory reset снова запускать `fprintd-enroll`
- Для текущего проекта порядок должен быть строже:
  - сначала `fprintd-list "$USER"`;
  - затем `fprintd-enroll "$USER"`;
  - затем `fprintd-verify "$USER"`;
  - только после успешного verify рассматривать PAM/authselect/GDM/sudo.

## Патчи, которые могут понадобиться

- `patches/open-fprintd-python314.patch`:
  - заменить `GObject.MainLoop()` на `GLib.MainLoop()`, если runtime подтвердит проблему;
  - заменить `self.devices.values()` на `list(self.devices.values())`, если D-Bus marshalling подтвердит проблему.
- `patches/python-validity-python314.patch`:
  - исправить неопределённый `winbio_name` в error path `EnrollStart`;
  - адаптировать пути запуска под `/opt/fedora-validity`, если это будет удобнее сделать patch-ем, а не wrapper-скриптом.

Патчи пока не применялись: синтаксис на Python 3.14 проходит, а runtime-проблемы нужно подтверждать в foreground debug-запусках.

## prepare-venv result 2026-05-18

- Создан `scripts/prepare-venv.sh`.
- `bash -n scripts/prepare-venv.sh` прошёл успешно.
- Подготовка `/opt/fedora-validity/venv` в этой сессии не выполнена, потому что `sudo -v` запросил пароль пользователя `serty`, а пароль не был введён.
- Скрипт использует `python3 -m venv --system-site-packages`, чтобы `dbus` и `gi` могли приходить из Fedora RPM (`python3-dbus`, `python3-gobject`), а `cryptography`, `pyusb`, `pyyaml`, `pip`, `setuptools`, `wheel` ставились внутри venv.

## prepare-venv note 2026-05-18T02:25:24+03:00

Venv `/opt/fedora-validity/venv` создан с `--system-site-packages`; `dbus` и `gi` доступны из Fedora RPM/system site-packages.
