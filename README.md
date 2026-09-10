# VisualVoice

> 청각장애가 있는 비즈니스 사용자를 위한 macOS **온디바이스 실시간 자막 · 녹취 · 회의록 · 실시간 번역** 통합 앱

![platform](https://img.shields.io/badge/platform-macOS%2026%2B%20%C2%B7%20Apple%20Silicon-blue)
![swift](https://img.shields.io/badge/Swift%206-SwiftUI-orange)
![languages](https://img.shields.io/badge/%EC%96%B8%EC%96%B4-%ED%95%9C%EA%B5%AD%EC%96%B4%20%C2%B7%20%EC%98%81%EC%96%B4%20%C2%B7%20%EC%9D%B8%EB%8F%84%EB%84%A4%EC%8B%9C%EC%95%84%EC%96%B4-green)
![license](https://img.shields.io/badge/license-Proprietary-lightgrey)

<img src="VisualVoice/Assets.xcassets/AppIcon.appiconset/icon_128.png" alt="VisualVoice 아이콘" width="96" align="right">

VisualVoice는 **앞에 있는 사람의 말(마이크)** 과 **온라인 미팅의 소리(시스템 오디오)** 를 실시간 자막으로 보여주고, 한국어·영어·인도네시아어를 발화마다 자동 감지해 상대 언어로 번역하며, 세션이 끝나면 회의록을 자동으로 작성합니다. Mac 기본 실시간 자막과 별도의 녹취 앱을 번갈아 쓰던 두 흐름을 한 창에 합치고 번역을 더한 것이 출발점입니다.

**전 과정이 기기 안에서 끝납니다.** 음성·자막·번역·회의록 어느 것도 서버로 보내지 않고, 최초 1회 언어팩·모델을 내려받은 뒤에는 완전 오프라인으로 동작합니다.

> ⚠️ **개인 프로젝트입니다.** 자체 서명 로컬 빌드 전용이며(공증·배포 없음), 텔레메트리와 개인 정보 수집이 없습니다.

---

## ✨ 주요 기능

### 실시간 자막
- 🎙 **대면 대화** — 마이크로 앞사람과의 대화를 실시간 자막
- 🖥 **온라인 미팅** — 줌·팀즈 등 **상대 소리(시스템 오디오)와 내 마이크를 동시에** 캡처. 내 발화는 항상 `나`로 기록되고, 상태바의 **내 마이크** 토글로 끌 수 있습니다
- 🔀 **엔진 자동 라우팅** — 한국어·영어 = Apple SpeechTranscriber, 인도네시아어 = WhisperKit large‑v3 turbo. 전부 온디바이스
- 🌐 **언어 1 · 언어 2** — 두 언어가 같으면 자막만, 다르면 자막 + 번역. 발화마다 언어를 자동 감지해 상대 언어로 번역하며, 마지막 선택을 기억합니다
- 👥 **화자 칩** — `나` / `상대 N`, 색과 텍스트를 함께 표기(색각 대응). 불확실한 화자는 점선 칩
- 🔠 **자막 크기 70 ~ 180 %** 를 라이브 화면·팝아웃·설정 어디서나, **밀도**(간결/상세), 원문·번역 **이중 표기** 토글
- 📌 **항상‑위 자막 패널**(팝아웃) — 메인 창이 가려지거나 최소화되면 자동으로 뜨고, 돌아오면 자동으로 닫힙니다
- ⬇️ **자동 스크롤 + '새 자막 N개' 배지** — 위로 올려 읽는 동안 도착한 자막을 놓치지 않게
- ⌨️ **타이핑 발화** — 내가 친 문장을 대화 흐름에 넣고, 상대 언어로 번역해 **읽어주기**(음성 합성)로 상대에게 들려줍니다. 재생 중에는 마이크를 잠시 닫아 자기 소리가 자막이 되는 것을 막습니다
- 👁 **소리를 눈으로** — 입력 레벨 미터(온라인 미팅은 마이크·시스템 2계통), 무음 경고, 내장 스피커 사용 경고, 마이크·녹음·번역 실패 배너

### 인식 품질
- 🧠 **음성 분류 기반 전사 게이트** — 절대 음량이 아니라 "사람 말인가"로 판정해 1 m 밖 상대 발화도 잡고, 소음이 자막으로 둔갑하는 환각은 4중으로 막습니다
- 🧭 **2언어 쌍 클램프·대화 관성** — 자동 감지가 선택하지 않은 제3 언어로 새지 않습니다
- ✂️ **문장 확정 규칙** — 종결부호 인지, 무음 분절, 잘린 문장 병합, 어두 프리롤, 경계 오버랩
- 🧪 **쉼 없이 이어지는 말 조기 확정(실험)** — 두 사람이 쉼 없이 주고받을 때 앞 문장을 먼저 확정해 한 줄로 뭉치거나 언어가 섞이는 것을 줄입니다(설정 › 인식)

### 화자
- 🎯 **실시간 화자 분리**(FluidAudio) — 칩을 눌러 **나로 지정** · **숨기기**(자막만, 녹취록엔 보존)
- ✏️ **세션 상세에서 화자 재지정** — 이 줄만 / 같은 화자 전부. 직접 지정한 줄은 이후 자동 재계산이 덮지 않습니다
- 🔁 **화자 다시 인식** — 녹음 원음으로 종료 후 정밀 재계산(인원 자동 추정 또는 2~5명 지정)

### 번역
- ⚡ **실시간** — Apple Translation(문장 단위, 온디바이스)
- ✦ **AI 재번역** — 세션이 끝나면 앱에 내장된 MLX Gemma 모델이 문맥을 보며 다시 번역합니다. 실시간 번역은 지우지 않고 별도 보관 — 토글로 비교하고, 줄에 마우스를 올리면 원래 번역이 보입니다. 일부만 성공하면 "N줄 중 M줄" 로 정직하게 표기

### 회의록
- 📝 **자동 작성**(FoundationModels, 온디바이스) — 요약 · 핵심 결정 · 할 일 · 참여 인원
- 🔗 **근거 타임코드 칩** — 결정·할 일마다 근거 발화로 점프. 근거를 못 찾은 항목엔 **확인 필요** 배지가 자동으로 붙습니다
- 👤 **참여 인원 정정** — 이름을 못 맞힌 자리는 추정 역할을 보여주고 클릭해 바로 고칩니다
- 🔄 **회의록 다시 만들기** — 실패했거나 Apple Intelligence를 나중에 켠 경우. 직접 고친 이름은 유지

### 세션 · 기록
- 💾 **자동 저장** — 녹취록·회의록·번역과 함께 날짜·엔진·모델·**기록 조건**(마이크 실패, 오디오 끊김 복구 횟수, 번역 실패 줄 수 등)을 남깁니다
- 🗂 **기록 보관함** — 제목·미리보기·녹취록 원문·번역 전문 검색, 제목 인라인 편집
- 🎧 **세션 음원 녹음** — 원음과 인식 음원을 WAV로 저장(세션 삭제 시 함께 삭제, 강제 종료 시 헤더 자동 복구, 설정에 사용량 표시)
- 📜 **이 녹음 다시 전사** — 녹음 전체를 통째로 전사한 대본을 라이브 자막과 대조
- 🔤 **치환 규칙** — 인식기가 자주 틀리는 이름·브랜드·전문용어를 화면과 내보내기에서 바로잡습니다. 저장된 원문은 그대로(줄에 마우스를 올리면 원문 확인)
- 📤 **내보내기** — TXT · Markdown · PDF · DOCX · JSON, 토글: 타임코드 · 화자 라벨 · 원문+번역 · 회의록 · 녹취록 · 군말 제거 · AI 재번역

### 정직 표기 원칙
- 잠정·추정·불확실을 확정처럼 보이게 하지 않습니다(잠정 배지, 점선 칩, 확인 필요 배지, ✦ 마커)
- 실패는 침묵하지 않습니다 — 저장·번역·녹음·마이크 실패는 배너로, 세션 기록에도 남깁니다
- 없는 수치를 만들지 않습니다(예: 날짜를 알 수 없는 옛 세션은 "날짜 미상")

---

## 🖥 화면

온보딩(권한·언어팩) · 홈(새 세션 — 언어 1·2, 캡처 모드 타일) · 라이브 · 자막 패널(팝아웃) · 세션 상세(녹취록 · 회의록 · 재전사 대본) · 기록 보관함 · 설정 · 내보내기 시트

---

## 🧰 요구사항

- **macOS 26 (Tahoe) 이상, Apple Silicon 전용** — SpeechAnalyzer · Translation · FoundationModels · ScreenCaptureKit 오디오 캡처가 모두 26+/Apple Silicon 전용입니다. Intel Mac은 지원하지 않습니다
- **Xcode 26+** (Swift 6 · SwiftUI)
- **Apple Intelligence 활성** — 회의록 작성과 실시간 번역의 고품질 전략에 사용됩니다(꺼져 있으면 사유를 표시하고 나머지 기능은 정상 동작)
- 저장 공간 — Apple 언어팩 + WhisperKit turbo 632 MB + FluidAudio 화자 모델 약 70 MB(자동 다운로드), **AI 재번역 모델 4.9 GB**(아래 "모델 준비")
- iPad(대면 대화 전용) 유니버설 타깃을 포함하지만 시뮬레이터 검증 단계입니다

---

## 🛠️ 빌드 & 설치

```bash
git clone https://github.com/LimMinGue/VisualVoice.git
cd VisualVoice

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project VisualVoice.xcodeproj -scheme VisualVoice \
           -configuration Release -destination 'platform=macOS,arch=arm64' \
           -derivedDataPath build/dd \
           -skipPackagePluginValidation -skipMacroValidation build
```

빌드 후 응용 프로그램 폴더로 설치:

```bash
ditto build/dd/Build/Products/Release/VisualVoice.app /Applications/VisualVoice.app
open /Applications/VisualVoice.app
```

한 번에 하려면 `build.sh`:

```bash
./build.sh          # Release 빌드
./build.sh -d       # Debug 빌드
./build.sh -i -r    # 빌드 → /Applications 설치 → 실행
./build.sh -h       # 옵션 도움말
```

> `-skipPackagePluginValidation -skipMacroValidation` 은 MLX 패키지의 빌드 플러그인·매크로가 헤드리스 빌드에서 신뢰 검증에 걸리는 것을 건너뜁니다 — 없으면 `BUILD FAILED`.
> `DEVELOPER_DIR=…` 접두는 `xcode-select`가 Command Line Tools를 가리키는 환경 대비입니다. Xcode가 이미 선택돼 있어도 무해합니다.
> 프로젝트 폴더를 옮긴 뒤 `There is no XCFramework found at <옛 경로>` 가 나오면 `rm -rf build/dd` 후 다시 빌드하세요.

### 코드 서명
프로젝트는 개발용 자체 서명 인증서(`CODE_SIGN_IDENTITY = "LimMinGue"`)로 설정돼 있습니다. 본인 환경에서는 인증서 이름을 바꾸거나(`xcodebuild … CODE_SIGN_IDENTITY="<본인 인증서>"`) ad‑hoc(`-`)으로 빌드하세요. 서명 신원이 바뀌면 macOS 권한(마이크·화면 기록)을 다시 승인해야 합니다. 개발 단계라 Hardened Runtime은 꺼져 있습니다.

### 모델 준비
| 구성 요소 | 준비 방식 |
|---|---|
| Apple 언어팩(한국어·영어 STT, 번역팩) | 온보딩에서 사전 다운로드, 없으면 첫 사용 시 자동 |
| WhisperKit `large-v3-v20240930_turbo_632MB` | 온보딩 또는 첫 인도네시아어 세션에서 자동 다운로드(허깅페이스), 이후 오프라인 |
| FluidAudio 화자 모델 | 첫 화자 분리·화자 다시 인식 때 자동 다운로드 |
| **AI 재번역 모델(`RetransModel/`)** | **저장소에 포함되지 않습니다(4.9 GB).** `RetransModel/MODEL_SOURCE.txt`에 적힌 구성(Gemma 2 9B IT · MLX 4bit)을 그 폴더에 넣어 빌드하세요. 없으면 AI 재번역만 "모델이 앱에 없습니다"로 비활성되고 나머지는 정상입니다 |

### 권한 안내
- **마이크** — 대면 대화·온라인 미팅의 내 발화
- **화면 및 시스템 오디오 녹음** — 온라인 미팅의 상대 소리(오디오만 사용, 화면은 저장하지 않습니다). 승인 후 앱을 다시 실행해야 합니다
- **Apple Intelligence** — 회의록 작성, 실시간 번역 고품질 전략

### 데이터 위치
`~/Library/Application Support/VisualVoice/` — `sessions.json`(세션·녹취록·회의록), `recordings/`(세션 음원 WAV). 세션 파일을 읽지 못하면 원본을 `sessions.unreadable-<시각>.json`으로 보존하고 빈 목록으로 시작합니다.

---

## 🏗️ 설계 노트

- **온디바이스 우선** — STT · 화자 분리 · 번역 · 회의록 전 파이프라인이 기기 안. 네트워크는 모델 최초 다운로드에만
- **입력 스트림 분리** — 마이크(나)와 시스템 오디오(상대)를 섞지 않아 1차 화자 신호를 공짜로 얻습니다
- **실시간 근사 + 종료 후 정밀** — 라이브는 지연이 생명이라 최소 처리, 정밀 작업(AI 재번역·화자 다시 인식·재전사)은 세션이 끝난 뒤 명시적으로
- **실시간 경로 불변** — 대형 모델·문맥 주입은 실시간에 투입하지 않습니다
- **공용 컴포넌트 단일화** — 자막 렌더(창 안 라이브 뷰 = 팝아웃), 배너, 설정 행 등 반복 UI는 하나의 컴포넌트
- **다크 단일 테마** — 영상 위 가독성을 위해 의도적으로 고정

---

## 🧩 서드파티

| 구성 요소 | 용도 | 라이선스 |
|---|---|---|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) 0.18.0 | 인도네시아어 STT · 녹음 재전사 | MIT |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | 실시간 화자 분리(LS‑EEND) · 종료 후 화자 재계산 | Apache‑2.0 |
| [mlx-swift](https://github.com/ml-explore/mlx-swift) 0.31.6 · [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) 3.31.4 | AI 재번역 모델 구동 | MIT |
| [swift-transformers](https://github.com/huggingface/swift-transformers) 1.1.9 · [swift-jinja](https://github.com/huggingface/swift-jinja) 2.4.1 | 토크나이저·프롬프트 템플릿 | Apache‑2.0 |
| Gemma 2 9B IT(MLX 4bit) | AI 재번역 모델(별도 준비) | [Gemma Terms of Use](https://ai.google.dev/gemma/terms) |

전체 목록과 라이선스 링크는 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)에 있습니다.

---

## 📝 변경 이력

버전별 상세 내용은 [CHANGELOG.md](CHANGELOG.md)를 참고하세요.

---

## 📄 라이선스

**독점 라이선스**(Proprietary) — © 2026 LimMinGue. All rights reserved. 자세한 조건은 [LICENSE](LICENSE)를 참고하세요.
동반 오픈 소스 구성 요소는 각자의 라이선스를 따릅니다([서드파티](#-서드파티) 참조).

버그 리포트 및 문의: iamwhatiam78@gmail.com
