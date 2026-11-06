# 📚 zlibx

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![Android](https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)
![Open Source](https://img.shields.io/badge/オープンソース-❤️-green?style=for-the-badge)
![License](https://img.shields.io/badge/License-AGPL--3.0-green?style=for-the-badge)

**スリムなAndroid専用電子書籍リーダー —— 64ビットのみ、AI機能なし、WeReadなし**

**サードパーティクライアント • フロントエンドインターフェースのみ • 外部ソースからのデータ**

[APKをダウンロード](https://github.com/minglaiyo/zlibx/releases) • [バグを報告](../../issues) • [機能をリクエスト](../../issues)

**[English](README.md)** | **[简体中文](README_ZH.md)** | **日本語** | **[한국어](README_KO.md)**

</div>

---

> ⚠️ **免責事項**: zlibxは独立したオープンソースのサードパーティクライアントです。公式クライアントではなく、いかなる公式サービスとも関連していません。このプロジェクトはフロントエンドインターフェースのみを提供し、すべての書籍データは外部ソースから取得されます。ご自身の判断でお使いください。

## ✨ 機能

| 機能 | 説明 |
|------|------|
| 📖 **書籍検索** | タイトル、著者、ISBN、キーワードで書籍を検索 |
| 🌙 **ダークモード** | 目に優しい読書体験 |
| 🌍 **多言語対応** | 英語、中文、日本語、한국어の5つの言語をサポート |
| 🔐 **マルチアカウント** | 複数のアカウントをシームレスに切り替え |
| 🔗 **マルチドメイン** | 複数のサーバーラインから選択 |
| 🆓 **完全無料** | 広告なし、サブスクリプションなし、隠れたコストなし |

## ✂️ このフォークについて

zlibx は shiyi-0x7f/olib-mobile を大幅に改造したフォークです：
- Android専用、64ビット（`arm64-v8a`）のみ
- AI機能を削除（処方箋検索、AI検索、バックエンド認証）
- WeReadを削除
- 元の非公開プラグインをこのリポジトリ内で書き直し

## 📱 スクリーンショット

<div align="center">
<i>近日公開予定...</i>
</div>

## 🚀 クイックスタート

### 前提条件

- Flutter SDK 3.10+
- Android Studio / VS Code
- Androidデバイスまたはエミュレータ

### インストール

```bash
# リポジトリをクローン
git clone https://github.com/minglaiyo/zlibx.git

# プロジェクトディレクトリに移動
cd zlibx

# 依存関係をインストール
flutter pub get

# アプリを実行
flutter run
```

### APKをビルド

```bash
flutter build apk --release --target-platform android-arm64
```

## 🏗️ プロジェクト構成

```
lib/
├── constants/      # 定数
├── core/           # コアロジック（書籍データ、サーバーライン）
├── l10n/           # ローカライゼーションファイル (5つの言語)
├── models/         # データモデル
├── providers/      # 状態管理 (Riverpod)
├── routes/         # アプリナビゲーション
├── screens/        # UI画面
├── services/       # API & ストレージサービス
├── theme/          # アプリテーマ設定
├── utils/          # ヘルパーユーティリティ
└── widgets/        # 再利用可能なコンポーネント

vendor/
└── olib_api_plugin/  # 元の非公開プラグインをこのリポジトリ内で書き直したもの
```

## 🛠️ 技術スタック

- **フレームワーク**: Flutter
- **状態管理**: Riverpod
- **ローカルストレージ**: Hive
- **HTTPクライアント**: Dio（http パッケージは検索候補と更新チェックのみで使用）
- **多言語**: 5つの言語

## 🤝 コントリビューション

コントリビューションを歓迎します！お気軽にPull Requestを提出してください。

1. プロジェクトをフォーク
2. 機能ブランチを作成 (`git checkout -b feature/AmazingFeature`)
3. 変更をコミット (`git commit -m 'Add some AmazingFeature'`)
4. ブランチにプッシュ (`git push origin feature/AmazingFeature`)
5. Pull Requestを開く

## 📄 ライセンス

このプロジェクトはGNU Affero General Public License v3.0（AGPL-3.0）の下でライセンスされています - 詳細は[LICENSE](LICENSE)ファイルをご覧ください。shiyi-0x7f/olib-mobile由来の部分はMITライセンスのままです（LICENSEファイルに保持）。

> ⚠️ **法的通知**: 
> - これは独立したサードパーティクライアントであり、公式アプリケーションではありません
> - すべての書籍データは外部ソースから取得され、このプロジェクトはフロントエンドのみを提供します
> - ユーザーは適用法への準拠を確認する責任があります
> - このソフトウェアを使用することで、これらの条件を認めたことになります

## 💖 謝辞

- shiyi-0x7f/olib-mobile（MIT）を基にスリム化
- Anna's Archive / LibGen ソースは warreth/OpenlibExtended（AGPL-3.0）より
- 💙 Flutterフレームワーク
- ❤️ オープンソースコミュニティ

---

<div align="center">

**[⬆ トップに戻る](#-zlibx)**

オープンソース • 永久に無料

</div>
