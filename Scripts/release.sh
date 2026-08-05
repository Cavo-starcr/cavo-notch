#!/bin/bash
# Выпуск версии: тег в гите и релиз на GitHub с приложенным образом.
#
# Номер берется из Scripts/version — единственного места, где он записан.
# Оттуда же он попадает в Info.plist приложения и в имя .dmg, так что тег,
# приложение и файл не могут разойтись: расходятся они молча, а замечается
# это у того, кому образ отдали.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(sed -n 's/^VERSION=//p' "$ROOT/Scripts/version")"
TAG="v$VERSION"
DMG="$ROOT/build/Cyclop-$VERSION.dmg"

cd "$ROOT"

fail() { echo "!!! $1" >&2; exit 1; }

command -v gh >/dev/null || fail "нужен gh: brew install gh"
gh auth status >/dev/null 2>&1 || fail "gh не авторизован: gh auth login"

# Тег указывает на коммит, а не на рабочее дерево. Если в дереве есть
# несохраненное, тег будет указывать не на то, что собрано.
[ -z "$(git status --porcelain)" ] || fail "есть несохраненные изменения — закоммить их сначала"

git fetch --quiet origin
[ -z "$(git rev-list @{u}..HEAD 2>/dev/null)" ] || fail "есть незапушенные коммиты — тег указывал бы на то, чего нет на GitHub"

if git rev-parse "$TAG" >/dev/null 2>&1; then
    fail "тег $TAG уже есть. Подними номер в Scripts/version"
fi

echo "==> сборка образа $VERSION"
"$ROOT/Scripts/dmg.sh" >/dev/null
[ -f "$DMG" ] || fail "образ не собрался: $DMG"

echo "==> тег $TAG"
git tag -a "$TAG" -m "Cyclop $VERSION"
git push --quiet origin "$TAG"

echo "==> релиз на GitHub"
# Заметки собираются из коммитов с прошлого тега: писать их вручную значит
# писать их дважды, а расходятся они уже на второй версии.
gh release create "$TAG" "$DMG" \
    --title "Cyclop $VERSION" \
    --generate-notes \
    --latest

echo "==> готово"
gh release view "$TAG" --json url --jq '"    " + .url'

if ! gh repo view --json visibility --jq '.visibility' | grep -qi public; then
    cat <<'NOTE'

    Репозиторий приватный, поэтому ссылка на релиз откроется только у тех,
    у кого есть доступ к нему. Чтобы образ мог скачать кто угодно по ссылке,
    репозиторий нужно сделать публичным.
NOTE
fi
