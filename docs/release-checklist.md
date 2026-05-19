# Release checklist

Перед публикацией на GitHub:

- [ ] Проверить, что репозиторий не содержит `docs/diagnostics-*.log`.
- [ ] Проверить, что нет `fedora-validity-setup.zip` или других локальных архивов.
- [ ] Проверить, что `third_party/` не попадает в commit или release archive.
- [ ] Если локальный `third_party/` содержит root-owned build remnants, убрать его из release archive; при необходимости удалить вручную из интерактивного терминала через `sudo rm -rf third_party.root-owned.local`.
- [ ] Проверить, что нет upstream `.git`, `build/`, `*.egg-info/`, `__pycache__/`.
- [ ] Проверить, что в publishable docs нет USB serial и локального username вне исторического контекста.
- [ ] Проверить, что README явно говорит: PAM/GDM/sudo integration не выполняется.
- [ ] Проверить, что `docs/install.md`, `docs/rollback.md`, `docs/security-and-privacy.md` актуальны.
- [ ] Выполнить `bash -n scripts/*.sh tests/*.sh`.
- [ ] Выполнить `for test in tests/*.sh; do bash "$test"; done`.
- [ ] Выполнить `systemd-analyze verify systemd/open-fprintd.service systemd/python3-validity.service`.
- [ ] Убедиться, что `scripts/install-systemd.sh --dry-run`, `scripts/rollback.sh --dry-run`, `scripts/clean-systemd-install.sh --dry-run` не показывают PAM/authselect/GDM изменений.
- [ ] Зафиксировать текущие upstream commits в `docs/upstream-commits.md`.
- [ ] Принять отдельное решение, публиковать ли patches в `patches/` как часть Fedora 44 / Python 3.14 compatibility layer.
