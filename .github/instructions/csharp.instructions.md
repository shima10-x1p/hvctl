---
description: "Use when writing or editing C# source files in this repository. Enforces the project's C# coding rules (XML doc comments on every member, no speculative interfaces/helpers, no mechanical try-catch, no backward-compat shims)."
applyTo: "src/**, tests/**"
---

# C# Coding Rules (short version)

完全版は [docs/coding-rules/csharp-coding-rules.md](../../docs/coding-rules/csharp-coding-rules.md) を参照。
本ファイルは **`.cs` 編集時に必ず守るべき遵守事項のサブセット**。

## 遵守事項

- **XML ドキュメントコメントを省略しない**。`public` / `internal` / `protected` / `private` を問わず、すべての型・メンバーに最低限 `<summary>` を書く。引数があれば `<param>`、戻り値があれば `<returns>`、意図的に投げる例外があれば `<exception>` を付ける。
- コメントは**コードの言い換えにしない**。書くのは **責務・意図・制約・判断理由**。「メッセージを追加します」のような空疎な文は禁止。
- **日本語で短く自然に**書く。
- 既存コードの構成・命名・責務分離を尊重する。**指示されていないファイルを広範囲に変更しない**。
- **`Nullable` reference types を信頼する**。境界以外で `null` チェックを増やさない。
- **`try-catch` を機械的に追加しない**。例外を握り潰さない。
- **後方互換シム / フォールバック分岐を理由なく追加しない**（循環的複雑度を増やしてまで足さない）。
- **Analyzer 警告は原則修正する**。抑制する場合は `#pragma warning disable` の直前に **理由コメント** を必ず書く。
- 変更後に **`dotnet format`** と **`dotnet build`** が成功する状態を目指す。

## 禁止事項（Copilot / Codex 厳守）

- **1 実装しかない `interface` を作らない**（「差し替えたい境界」以外で `IFoo`/`FooImpl` を生やさない）。
- **不要な `helper` / `extension method` を作らない**。「将来必要かもしれない」は作る理由にならない。
- **継承で再利用しない**。コンポジションを使う。`class` / `record` は **`sealed` をデフォルト**にする。
- 既存設計（フォルダ構成、レイヤ分離）を無視して**新しい構成を作らない**。
- `async void` をイベントハンドラ以外で使わない。`.Result` / `.Wait()` / `.GetAwaiter().GetResult()` で同期待ちしない。

## 構文選択の素早い判断

- `namespace` は **file-scoped** で書く。
- `record` は DTO・メッセージ・イベント用。振る舞いがあれば `class`。
- `primary constructor` は **DI で依存だけ受け取る薄いクラス** か `record` のみ。バリデーション / 加工があるドメインクラスでは通常の constructor を使う。
- `expression-bodied member` は **1 行で意味が取れる** ときだけ。条件式の連鎖を 1 行に詰め込まない。
- `switch expression` は分岐が複雑になったら通常の `switch` 文に戻す。
- `extension members` は雑多な便利関数置き場にしない。
- `field` keyword は単純な property validation / 正規化など意味が明確な場面のみ。
- `var` は右辺から型が明らかなときだけ。設計上重要な戻り値型は明示する。

## async メソッド規約

- 名前は **`Async`** で終える。
- `CancellationToken` は**最後の引数**に置く。
- ライブラリ層（同期コンテキスト非依存）では `ConfigureAwait(false)` を付ける。アプリケーション層では原則付けない。

## メソッド設計

- AI は**理由のない関数分割をしてはいけない**。`private` メソッドを切るのは「**名前で意味が増える**」か「**複数箇所で使われる**」場合のみ。
- 引数が 4 個以上 or 増える見込みなら `record` の `Request` / `Options` 型を検討する。

## 迷ったときの優先順位

1. 既存コードのパターンに合わせる
2. シンプルさ（YAGNI / KISS）
3. 型と Nullable で表現する
4. このルール
5. 新しい構文の魅力

**新しい構文を使うために既存パターンを崩してはいけない。**
このルールに反する提案をする場合は、**変更理由・代替案・影響範囲**を明記すること。
