#!/bin/sh
# VisualVoice 빌드 스크립트 — README의 xcodebuild 커맨드를 한 줄로
#
#   ./build.sh            Release 빌드
#   ./build.sh -d         Debug 빌드
#   ./build.sh -i         빌드 후 /Applications 에 설치
#   ./build.sh -i -r      설치 후 실행 (-r 만 주면 빌드한 자리에서 실행)
#   ./build.sh -c         빌드 전 build/ 캐시 삭제(프로젝트 폴더를 옮긴 뒤 XCFramework 경로 오류가 날 때)
#
# VV_SIGN_IDENTITY="인증서 이름" 을 지정하면 그 인증서로 서명합니다(프로젝트 기본값은 "LimMinGue").
# 서명 신원이 바뀌면 macOS 권한(마이크·화면 기록)을 다시 승인해야 하므로, 한 번 정한 인증서를
# 계속 쓰는 것이 편합니다. ad-hoc 서명은 VV_SIGN_IDENTITY="-".
#
# AI 재번역 모델(RetransModel/)은 저장소에 없습니다 — RetransModel/MODEL_SOURCE.txt 참조.
# 없어도 빌드·실행은 되고 AI 재번역만 비활성됩니다.

set -eu
cd "$(dirname "$0")"

CONFIG=Release
INSTALL=0
RUN=0
CLEAN=0
for arg in "$@"; do
    case "$arg" in
        -d|--debug)   CONFIG=Debug ;;
        -i|--install) INSTALL=1 ;;
        -r|--run)     RUN=1 ;;
        -c|--clean)   CLEAN=1 ;;
        -h|--help)    sed -n '2,15p' "$0" | cut -c 3-; exit 0 ;;
        *) echo "알 수 없는 옵션: $arg  (도움말: ./build.sh -h)" >&2; exit 2 ;;
    esac
done

# xcode-select가 Command Line Tools를 가리키는 환경 대비 — 이미 Xcode면 무해 (README)
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [ "$CLEAN" = 1 ]; then
    echo "▶︎ 빌드 캐시 삭제: build/"
    rm -rf build
fi

if [ ! -f RetransModel/config.json ]; then
    echo "ℹ︎ RetransModel/ 에 모델이 없습니다 — AI 재번역은 비활성으로 빌드됩니다 (RetransModel/MODEL_SOURCE.txt 참조)"
fi

SIGN_ARGS=""
if [ -n "${VV_SIGN_IDENTITY:-}" ]; then
    SIGN_ARGS="CODE_SIGN_IDENTITY=$VV_SIGN_IDENTITY"
fi

echo "▶︎ $CONFIG 빌드…"
# -skipPackagePluginValidation -skipMacroValidation: MLX 패키지의 플러그인·매크로 신뢰 검증을
# 헤드리스 빌드에서 건너뜀 — 없으면 "Validate plug-in CudaBuild" 단계에서 BUILD FAILED.
if ! xcodebuild -project VisualVoice.xcodeproj -scheme VisualVoice \
                -configuration "$CONFIG" -destination 'platform=macOS,arch=arm64' \
                -derivedDataPath build/dd \
                -skipPackagePluginValidation -skipMacroValidation \
                ${SIGN_ARGS:+"$SIGN_ARGS"} build; then
    echo >&2
    echo "✗ 빌드 실패. 'There is no XCFramework found at …' 오류라면: ./build.sh -c 로 캐시를 지우고 다시 빌드하세요." >&2
    exit 1
fi

APP="build/dd/Build/Products/$CONFIG/VisualVoice.app"
TARGET="$APP"

if [ "$INSTALL" = 1 ]; then
    # 실행 중이면 ditto가 덮어쓴 뒤에도 옛 프로세스가 남아 혼동 — 먼저 종료
    osascript -e 'tell application "VisualVoice" to quit' 2>/dev/null || true
    echo "▶︎ /Applications/VisualVoice.app 로 설치…"
    rm -rf /Applications/VisualVoice.app
    ditto "$APP" /Applications/VisualVoice.app
    codesign --verify --deep --strict /Applications/VisualVoice.app && echo "▶︎ 서명 검증 통과"
    TARGET=/Applications/VisualVoice.app
fi

if [ "$RUN" = 1 ]; then
    echo "▶︎ 실행: $TARGET"
    open "$TARGET"
fi

echo "✓ 완료 — $TARGET"
