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
- локальный venv/cache под `/opt/fedora-validity`;
- optional PAM/authselect backup/state под `/opt/fedora-validity/backups` и
  `/opt/fedora-validity/state`.

PAM/GDM/sudo integration выполняется только отдельными script entrypoints:

- `scripts/check-pam-state.sh` read-only;
- `scripts/enable-pam.sh` через `authselect enable-feature with-fingerprint`;
- `scripts/disable-pam.sh` через `authselect disable-feature with-fingerprint`.

`scripts/project-menu.sh` является dispatcher-слоем и не добавляет отдельный
путь системных изменений. Он вызывает только documented project scripts:
service checks, service restart/install, enrollment check, PAM guards и
rollback.

Остальные install/systemd/rollback скрипты не вызывают `authselect` и не
редактируют `/etc/pam.d`, GDM или sudo policy.

`enable-pam.sh` не отключает password fallback и не редактирует PAM через
`sed`. Если `with-fingerprint` уже был включён до проекта, он фиксирует факт и
не создаёт project marker для последующего отключения. `disable-pam.sh` без
`--force` не отключает fingerprint без project marker.

## Firmware cache

Persistent firmware cache хранится в `/opt/fedora-validity/firmware/python-validity`. Он нужен, чтобы `python3-validity.service` не зависел от DNS/network на раннем boot.

## Диагностика

`scripts/collect-diagnostics.sh` может собирать чувствительные данные: USB serial, usernames, локальные пути, journal/audit записи и состояние authentication stack. Логи диагностики предназначены только для локального анализа.

`scripts/check-pam-state.sh` выводит локальный authentication state:
`authselect current`, найденные `pam_fprintd.so`, installed packages,
service status и enrolled fingerprint names. Не публиковать этот вывод без
проверки usernames и локальных путей.

## Browser authentication boundary

Fingerprint support в этом проекте ограничен локальным Linux authentication
stack. Он не создаёт FIDO2/WebAuthn authenticator, не регистрирует passkeys и
не позволяет использовать Validity `138a:0097` как security key для GitHub или
других сайтов. Для browser 2FA/passkeys нужен отдельный совместимый
authenticator: hardware FIDO2 key, phone passkey, password manager passkey или
поддерживаемый platform authenticator.
