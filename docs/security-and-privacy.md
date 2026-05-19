# Security and privacy

## Публикационные правила

Не публиковать:

- `docs/diagnostics-*.log`;
- `fedora-validity-setup.zip`;
- локальные `third_party/` clones;
- upstream `.git` directories;
- `build/`, `*.egg-info/`, cache и backup outputs;
- USB serial, локальные usernames, journal/audit фрагменты и приватные пути без явного решения.

Эти файлы и каталоги добавлены в `.gitignore`, но перед публикацией всё равно нужно проверить `git status --ignored` или содержимое архива.

## Системные изменения

Проект устанавливает только явно описанные артефакты:

- D-Bus policy files в `/etc/dbus-1/system.d`;
- systemd unit files в `/etc/systemd/system`;
- helper `/opt/fedora-validity/bin/ensure-firmware.sh`;
- локальный venv/cache под `/opt/fedora-validity`.

PAM/GDM/sudo integration не выполняется. `authselect` не вызывается install/systemd/rollback скриптами.

## Firmware cache

Persistent firmware cache хранится в `/opt/fedora-validity/firmware/python-validity`. Он нужен, чтобы `python3-validity.service` не зависел от DNS/network на раннем boot.

## Диагностика

`scripts/collect-diagnostics.sh` может собирать чувствительные данные: USB serial, usernames, локальные пути, journal/audit записи и состояние authentication stack. Логи диагностики предназначены только для локального анализа.
