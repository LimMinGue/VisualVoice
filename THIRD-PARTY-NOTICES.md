# 서드파티 고지 (Third-Party Notices)

VisualVoice는 아래 오픈 소스 구성 요소를 Swift Package Manager로 함께 빌드합니다. 각 구성 요소는 자체 라이선스를 따르며, 라이선스 원문은 각 저장소와 빌드 시 내려받는 패키지 체크아웃(`build/dd/SourcePackages/checkouts/<이름>/LICENSE*`)에 있습니다.

| 구성 요소 | 버전 | 용도 | 라이선스 |
|---|---|---|---|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | 0.18.0 | 인도네시아어 실시간 STT · 녹음 재전사 | [MIT](https://github.com/argmaxinc/WhisperKit/blob/main/LICENSE.md) |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | 300165b(리비전 고정) | 실시간 화자 분리(LS‑EEND) · 종료 후 화자 재계산 | [Apache‑2.0](https://github.com/FluidInference/FluidAudio/blob/main/LICENSE) |
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | 0.31.6 | AI 재번역 모델 구동(Apple Silicon) | [MIT](https://github.com/ml-explore/mlx-swift/blob/main/LICENSE) |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | 3.31.4 | 언어 모델 로드·생성 | [MIT](https://github.com/ml-explore/mlx-swift-lm/blob/main/LICENSE) |
| [swift-transformers](https://github.com/huggingface/swift-transformers) | 1.1.9 | 토크나이저·허깅페이스 허브 클라이언트 | [Apache‑2.0](https://github.com/huggingface/swift-transformers/blob/main/LICENSE) |
| [swift-jinja](https://github.com/huggingface/swift-jinja) | 2.4.1 | 프롬프트 템플릿 | [Apache‑2.0](https://github.com/huggingface/swift-jinja/blob/main/LICENSE) |
| [yyjson](https://github.com/ibireme/yyjson) | 0.12.0 | JSON 파싱(간접 의존) | [MIT](https://github.com/ibireme/yyjson/blob/master/LICENSE) |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) · [swift-asn1](https://github.com/apple/swift-asn1) · [swift-collections](https://github.com/apple/swift-collections) · [swift-crypto](https://github.com/apple/swift-crypto) · [swift-numerics](https://github.com/apple/swift-numerics) · [swift-syntax](https://github.com/swiftlang/swift-syntax) | 1.8.2 · 1.7.1 · 1.6.0 · 4.5.1 · 1.1.1 · 603.0.2 | 간접 의존(위 패키지들이 요구) | Apache‑2.0 |

## 런타임에 내려받는 모델

| 모델 | 출처 | 라이선스 |
|---|---|---|
| Whisper large‑v3 turbo(Core ML, `large-v3-v20240930_turbo_632MB`) | [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml) | MIT(OpenAI Whisper 가중치 MIT) |
| FluidAudio 화자 분리 모델(LS‑EEND · 오프라인 세그멘테이션/임베딩) | FluidAudio 모델 허브 | Apache‑2.0 / 각 모델 카드 참조 |
| Apple 언어팩(SpeechTranscriber · Translation) | Apple 시스템 자산 | Apple 소프트웨어 사용권 |

## 별도 준비 모델(저장소·앱에 미포함)

| 모델 | 구성 | 약관 |
|---|---|---|
| Gemma 2 9B IT(MLX 4bit) — `RetransModel/` | `RetransModel/MODEL_SOURCE.txt` 참조 | [Gemma Terms of Use](https://ai.google.dev/gemma/terms) — 사용자가 직접 동의·준비 |

## Apple 프레임워크
Speech(SpeechAnalyzer · SpeechTranscriber) · Translation · FoundationModels · ScreenCaptureKit · AVFoundation · SoundAnalysis · NaturalLanguage — macOS SDK 사용권에 따릅니다.
