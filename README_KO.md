# 📚 zlibx

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![Android](https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)
![Open Source](https://img.shields.io/badge/오픈소스-❤️-green?style=for-the-badge)
![License](https://img.shields.io/badge/License-AGPL--3.0-green?style=for-the-badge)

**슬림한 Android 전용 전자책 리더 —— 64비트 전용, AI 기능 없음, WeRead 없음**

**서드파티 클라이언트 • 프론트엔드 인터페이스만 제공 • 외부 소스에서 데이터**

[APK 다운로드](https://github.com/minglaiyo/olib-lite/releases) • [버그 신고](../../issues) • [기능 요청](../../issues)

**[English](README.md)** | **[简体中文](README_ZH.md)** | **[日本語](README_JA.md)** | **한국어**

</div>

---

> ⚠️ **면책 조항**: zlibx은 독립적인 오픈 소스 서드파티 클라이언트입니다. 공식 클라이언트가 **아니며** 어떤 공식 서비스와도 관련이 없습니다. 이 프로젝트는 프론트엔드 인터페이스만 제공하며 모든 책 데이터는 외부 소스에서 가져옵니다. 본인의 판단에 따라 사용하세요.

## ✨ 기능

| 기능 | 설명 |
|------|------|
| 📖 **책 검색** | 제목, 저자, ISBN 또는 키워드로 책 검색 |
| 💾 **오프라인 읽기** | 인터넷 없이 읽기 위해 책 다운로드 |
| 🌙 **다크 모드** | 눈에 편안한 읽기 경험 |
| 🌍 **다국어** | 영어, 中文, 日本語, 한국어 등 16개 이상의 언어 지원 |
| 🔐 **멀티 계정** | 여러 계정을 원활하게 전환 |
| 🔗 **멀티 도메인** | 여러 서버 라인 중 선택 |
| 🆓 **완전 무료** | 광고 없음, 구독 없음, 숨겨진 비용 없음 |

## ✂️ 이 포크에 대해

zlibx는 shiyi-0x7f/olib-mobile을 대폭 수정한 포크입니다:
- Android 전용, 64비트(`arm64-v8a`) 전용
- AI 기능 제거(처방 검색, AI 검색, 백엔드 인증)
- WeRead 제거
- 기존 비공개 플러그인을 이 저장소에서 처음부터 다시 작성

## 📱 스크린샷

<div align="center">
<i>곧 출시 예정...</i>
</div>

## 🚀 빠른 시작

### 전제 조건

- Flutter SDK 3.8+
- Android Studio / VS Code
- Android 기기 또는 에뮬레이터

### 설치

```bash
# 저장소 복제
git clone https://github.com/minglaiyo/olib-lite.git

# 프로젝트 디렉토리로 이동
cd olib-lite

# 종속성 설치
flutter pub get

# 앱 실행
flutter run
```

### APK 빌드

```bash
flutter build apk --release --target-platform android-arm64
```

## 🏗️ 프로젝트 구조

```
lib/
├── l10n/           # 로컬라이제이션 파일 (16개 이상 언어)
├── models/         # 데이터 모델
├── providers/      # 상태 관리 (Riverpod)
├── routes/         # 앱 네비게이션
├── screens/        # UI 화면
├── services/       # API & 스토리지 서비스
├── theme/          # 앱 테마 설정
└── widgets/        # 재사용 가능한 컴포넌트
```

## 🛠️ 기술 스택

- **프레임워크**: Flutter
- **상태 관리**: Riverpod
- **로컬 스토리지**: Hive
- **HTTP 클라이언트**: http 패키지
- **다국어**: 16개 이상 언어

## 🤝 기여

기여를 환영합니다! 자유롭게 Pull Request를 제출해 주세요.

1. 프로젝트 포크
2. 기능 브랜치 생성 (`git checkout -b feature/AmazingFeature`)
3. 변경 사항 커밋 (`git commit -m 'Add some AmazingFeature'`)
4. 브랜치에 푸시 (`git push origin feature/AmazingFeature`)
5. Pull Request 열기

## 📄 라이선스

이 프로젝트는 GNU Affero General Public License v3.0(AGPL-3.0) 하에 라이선스가 부여됩니다 - 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하세요. shiyi-0x7f/olib-mobile에서 파생된 부분은 MIT 라이선스를 유지합니다(LICENSE 파일에 보존).

> ⚠️ **법적 고지**: 
> - 이것은 독립적인 서드파티 클라이언트이며 공식 애플리케이션이 **아닙니다**
> - 모든 책 데이터는 외부 소스에서 가져오며 이 프로젝트는 프론트엔드만 제공합니다
> - 사용자는 해당 법률을 준수해야 할 책임이 있습니다
> - 이 소프트웨어를 사용함으로써 이러한 조건을 인정하게 됩니다

## 💖 감사의 말

- shiyi-0x7f/olib-mobile(MIT) 기반 경량화
- Anna's Archive / LibGen 소스는 warreth/OpenlibExtended(AGPL-3.0)에서 가져옴
- 💙 Flutter 프레임워크
- ❤️ 오픈 소스 커뮤니티

---

<div align="center">

**[⬆ 맨 위로](#-olib)**

오픈 소스 • 영원히 무료

</div>
