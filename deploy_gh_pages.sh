#!/usr/bin/env bash
# 원스텝서울 랜딩 2종 + 관리자 페이지 → GitHub Pages 재배포 스크립트
#
# 사용법:
#   bash deploy_gh_pages.sh                          # onestepseoul/onestepseoul.github.io
#   REPO=onestepseoul-event bash deploy_gh_pages.sh  # 다른 저장소에 올릴 때
#   bash deploy_gh_pages.sh --with-config            # (위험) 로컬 config*.json 까지 덮어쓸 때만
#
# 전제: 대상 저장소가 이미 존재해야 한다.
#
# 하는 일: 저장소를 작업 폴더에 클론 → index.html · support.html · admin.html · .nojekyll · images/ 복사
#          → 바뀐 게 있으면 커밋·푸시 → GitHub Pages 설정 확인
#          → / , /support.html , /admin.html , /config.json , /config-support.json 이 200 인지 확인
#
# ⚠️ config.json · config-support.json 은 **관리자 페이지가 직접 커밋하는 파일**입니다.
#    사장님이 admin.html 에서 저장한 최신 내용이 거기에 있으므로,
#    이 스크립트는 기본적으로 **두 파일을 건드리지 않습니다(원격 최신본 보존)**.
#    로컬 사본으로 덮어써야 하는 특별한 경우에만 --with-config 를 붙이세요.
set -euo pipefail

OWNER="${OWNER:-onestepseoul}"
REPO="${REPO:-onestepseoul.github.io}"
BRANCH="${BRANCH:-main}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${WORK:-/tmp/gh-pages-deploy-$REPO}"
WITH_CONFIG=0
for a in "$@"; do
  [ "$a" = "--with-config" ] && WITH_CONFIG=1
done

echo "== 0. 저장소 확인: $OWNER/$REPO"
gh api "repos/$OWNER/$REPO" --jq '"   " + .full_name + " | private=" + (.private|tostring) + " | default=" + .default_branch' \
  || { echo "!! 저장소가 없거나 접근 권한이 없습니다. github.com/new 에서 먼저 만들어 주세요."; exit 2; }

echo "== 1. 작업 폴더: $WORK"
if [ -d "$WORK/.git" ]; then
  git -C "$WORK" fetch -q origin && git -C "$WORK" reset -q --hard "origin/$BRANCH"
else
  rm -rf "$WORK"
  git clone -q --branch "$BRANCH" "https://github.com/$OWNER/$REPO.git" "$WORK" 2>/dev/null \
    || { mkdir -p "$WORK"; git -C "$WORK" init -q -b "$BRANCH"; git -C "$WORK" remote add origin "https://github.com/$OWNER/$REPO.git"; }
fi
# 원격의 두 설정 파일을 지금 상태로 백업 (커밋 전 비교·복원용)
REMOTE_CFG_SHA=""
REMOTE_SUP_SHA=""
[ -f "$WORK/config.json" ] && REMOTE_CFG_SHA="$(git -C "$WORK" rev-parse "HEAD:config.json" 2>/dev/null || true)"
[ -f "$WORK/config-support.json" ] && REMOTE_SUP_SHA="$(git -C "$WORK" rev-parse "HEAD:config-support.json" 2>/dev/null || true)"
git -C "$WORK" config user.name  "$OWNER"
git -C "$WORK" config user.email "$OWNER@users.noreply.github.com"

echo "== 2. 페이지 파일 복사 (설정 JSON 은 기본적으로 보존)"
cp "$SRC/index.html"   "$WORK/index.html"
[ -f "$SRC/support.html" ] && cp "$SRC/support.html" "$WORK/support.html"
cp "$SRC/admin.html"   "$WORK/admin.html"
: > "$WORK/.nojekyll"     # GitHub Pages가 Jekyll 처리를 건너뛰게 함

if [ "$WITH_CONFIG" = "1" ]; then
  echo "   --with-config: 로컬 config*.json 으로 덮어씁니다 (사장님이 관리자 페이지에서 저장한 내용은 사라집니다!)"
  cp "$SRC/config.json" "$WORK/config.json"
  [ -f "$SRC/config-support.json" ] && cp "$SRC/config-support.json" "$WORK/config-support.json"
else
  echo "   config.json · config-support.json → 원격 최신본 그대로 유지 (복사 안 함)"
fi

if [ -d "$SRC/images" ] && [ -n "$(ls -A "$SRC/images" 2>/dev/null || true)" ]; then
  mkdir -p "$WORK/images"
  cp -R "$SRC/images/." "$WORK/images/"
  echo "   images/ $(ls -1 "$SRC/images" | wc -l)개 복사"
else
  echo "   images/ 없음 — 건너뜀 (관리자 페이지에서 사진을 올리면 저장소에 생깁니다)"
fi

echo "== 3. 설정 JSON 이 실수로 바뀌지 않았는지 확인"
if [ "$WITH_CONFIG" = "0" ]; then
  now_cfg="$(git -C "$WORK" rev-parse "HEAD:config.json" 2>/dev/null || echo none)"
  now_sup="$(git -C "$WORK" rev-parse "HEAD:config-support.json" 2>/dev/null || echo none)"
  [ "$now_cfg" = "${REMOTE_CFG_SHA:-none}" ] || { echo "!! config.json 이 바뀌었습니다 — 중단"; exit 4; }
  [ "$now_sup" = "${REMOTE_SUP_SHA:-none}" ] || { echo "!! config-support.json 이 바뀌었습니다 — 중단"; exit 4; }
  echo "   확인 OK (두 설정 파일 그대로)"
fi

echo "== 4. 커밋 & 푸시"
cd "$WORK"
git add -A
if git diff --cached --quiet; then
  echo "   변경 없음 — 푸시 생략"
else
  git commit -q -m "원스텝서울 랜딩 · 관리자 페이지 업데이트 ($(date '+%Y-%m-%d %H:%M'))"
  git push -q -u origin "$BRANCH"
  echo "   푸시 완료: $(git log -1 --format='%h %s')"
fi

echo "== 5. GitHub Pages 설정 확인"
if gh api "repos/$OWNER/$REPO/pages" >/dev/null 2>&1; then
  echo "   이미 켜져 있음"
else
  gh api -X POST "repos/$OWNER/$REPO/pages" \
    -f 'source[branch]='"$BRANCH" -f 'source[path]=/' --jq '"   활성화: " + .html_url' \
    || echo "   !! Pages 활성화 실패 — 저장소 Settings > Pages 에서 브랜치를 직접 지정해야 할 수 있음"
fi

echo "== 6. 접속 확인"
BASE="https://$OWNER.github.io/$REPO"
[ "$REPO" = "$OWNER.github.io" ] && BASE="https://$OWNER.github.io"
for i in $(seq 1 24); do
  all_ok=1
  for p in "/" "/support.html" "/admin.html" "/config.json" "/config-support.json"; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE$p" || true)
    echo "  [$i] $BASE$p → HTTP $code"
    [ "$code" = "200" ] || all_ok=0
  done
  if [ "$all_ok" = "1" ]; then echo "OK: $BASE/ · /support.html · /admin.html · /config.json · /config-support.json"; exit 0; fi
  sleep 15
done
echo "!! 아직 200이 아닙니다. 몇 분 뒤 다시 확인하세요: $BASE/"
exit 3
