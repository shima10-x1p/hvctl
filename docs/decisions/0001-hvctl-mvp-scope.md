# 0001: hvctl のMVPスコープを定義する

## Status

Accepted

## Context

Hyper-V の VM を PowerShell や Hyper-V マネージャーで手作業管理すると、VM 一覧確認、起動、停止、IP 確認、SSH 接続、複数 VM のまとめ操作が面倒になる。

一方で、`hvctl` は Hyper-V の全機能を抽象化する管理フレームワークではなく、既存 VM の日常操作を短いコマンドで安全に行うための小さな CLI として始める。将来 WebAPI や WinUI に展開できる程度の責務分離は行うが、v0.1 では Console CLI のみを対象とする。

設定ファイルは、Hyper-V の望ましい状態を宣言する manifest ではなく、既存 VM を短い alias や stack/node として扱うためのローカル台帳として位置づける。

## Decision

v0.1 の対象は以下に限定する。

- VM 一覧表示。
- VM 起動。
- VM 停止。
- VM IP 表示。
- VM alias。
- SSH 接続。
- stack 単位の起動・停止。
- stack status 表示。

VM 作成、VHDX、ISO、仮想スイッチ、checkpoint、cloud-init、宣言的 apply、reconcile、GUI、WebAPI、常駐サービスは v0.1 の対象外とする。

リソース名は以下とする。

- `vm`: Hyper-V 上の実 VM、または alias / `<stack>/<node>` から解決される VM target。
- `stack`: 複数 VM の論理グループ。
- `node`: stack 内の VM 別名。

stack 内 node は `<stack>/<node>` で参照する。`--stack` / `-s` は v0.1 では提供しない。

CLI は以下を提供する。

```bash
hvctl get vm
hvctl start vm <target>
hvctl stop vm <target>
hvctl stop vm <target> --force
hvctl ip vm <target>
hvctl ssh <target>

hvctl get stack
hvctl status stack <stack-name>
hvctl start stack <stack-name>
hvctl stop stack <stack-name>
```

target 解決は以下とする。

- `/` を含む target は `<stack>/<node>` として解釈する。
- `/` を含まない target は `vms.yaml` の alias を探し、なければ Hyper-V VM 名として扱う。

設定ファイルは単一ファイルではなく、設定ディレクトリに分割して置く。

```txt
%USERPROFILE%\.hvctl\vms.yaml
%USERPROFILE%\.hvctl\stacks.yaml
```

`--config-dir <path>` で設定ディレクトリを指定できる。current directory の自動探索、config merge、`config.d`、`HVCTL_CONFIG` は v0.1 では扱わない。

`vms.yaml` は単体 VM alias の台帳、`stacks.yaml` は stack/node の台帳とする。`stacks.yaml` の node は `vmName` を直接持ち、`vms.yaml` の alias は参照しない。

設定ファイルは `schemaVersion: hvctl/v1` を必須とする。未指定または未知の値は config error とする。未知フィールドも config error とする。

設定 validation は以下の二段構えとする。

- JSON Schema validation: 形、必須項目、型、未知フィールド、pattern、`ssh.port` 範囲。
- C# semantic validation: case-insensitive な alias / stack / node 重複。

JSON Schema は `.json` として repository に置き、実行時は embedded resource から読む。YAML 読み込みには `YamlDotNet`、JSON Schema validation には `JsonSchema.Net` を使う。

VM 名や target 名の扱いは以下とする。

- `alias`、`stack.name`、`node.name` は `^[A-Za-z0-9_.-]+$`。
- 解決と重複チェックは case-insensitive。
- 表示は設定ファイルに書かれた表記を維持する。
- `vmName` は空でないことだけ検証し、文字種制限しない。
- 同じ `vmName` の複数登録は許可する。

stack 操作は逐次実行とする。

- `start stack`: `nodes` 定義順。
- `stop stack`: `nodes` 逆順。
- 途中で失敗した場合はそこで停止し、以降の node は `not-run` として結果に含める。

stop の既定は graceful shutdown とする。強制停止は `--force` 指定時のみ行う。

```powershell
Stop-VM -Name <name> -Shutdown -Confirm:$false
Stop-VM -Name <name> -TurnOff -Confirm:$false
```

start/stop は Application 層で事前状態を確認し、目的状態なら `skipped` とする。操作後は 1 回だけ状態を再取得する。wait、retry、timeout は v0.1 では行わない。

SSH は `ssh.exe` の起動に限定する。`hvctl` は password、passphrase、agent、known_hosts を扱わない。`ssh.exe` は PATH 解決に任せ、stdin/stdout/stderr を継承し、`ssh.exe` の exit code をそのまま返す。

PowerShell 実行は Infrastructure に閉じ込める。Application / Domain は PowerShell の詳細を知らない。

PowerShell へのユーザー入力値は Base64 JSON payload で渡す。PowerShell スクリプト全体は UTF-16LE Base64 にして `-EncodedCommand` で渡す。PowerShell 出力は `ConvertTo-Json` を使い、常に配列として返す。

プロジェクト構成は以下の方針とする。

```txt
HvCtl.Core
  Application
  Domain
  Ports

HvCtl.Infrastructure
  HyperV
  Ssh
  Config

HvCtl.Console
  Commands
```

技術選定は以下とする。

- Target Framework: `net10.0`
- CLI parser: `System.CommandLine`
- YAML: `YamlDotNet`
- JSON Schema validation: `JsonSchema.Net`
- DI: `Microsoft.Extensions.DependencyInjection`
- Test framework: `xUnit`
- ログ基盤: v0.1 では入れない

## Consequences

この判断により、`hvctl` は小さく始められる。既存 VM の日常操作に集中し、Hyper-V の全機能を包む大きな抽象を避けられる。

設定ファイルをローカル台帳として扱うため、config がなくても `get vm` や実 VM 名指定の `start vm` / `stop vm` / `ip vm` は動作できる。これにより PoC と初期利用の負担が下がる。

Core / Application / Infrastructure / Console を分けることで、PowerShell、YAML、SSH 起動の詳細を Infrastructure に閉じ込められる。将来 WebAPI や WinUI に展開する場合も、Core を再利用しやすい。

JSON Schema validation を v0.1 から導入することで、設定ファイルの typo や未知フィールドを早期に検出できる。一方で、設定実装はやや重くなり、JSON Schema と C# semantic validation の二層を維持する必要がある。

stack 操作を逐次実行に限定することで、暗黙の依存順を YAML の node 順で表現できる。一方で、大きな stack の操作は並列実行より遅くなる。

`restart`、`--wait`、`dependsOn`、`--parallel` を入れないため、v0.1 は単純に保てる。一方で、複雑な運用には後続バージョンでの拡張が必要になる。

SSH 認証を `ssh.exe` に任せることで、`hvctl` は認証情報を保持せずに済む。一方で、SSH の詳細な制御や独自エラーハンドリングは行わない。

PowerShell への入力を Base64 JSON payload とし、`-EncodedCommand` を使うことで引用や特殊文字による壊れ方を減らせる。一方で、デバッグ時に実際のスクリプトと値が見えにくくなる。

## Alternatives Considered

### 単一 `config.yaml`

最初は `%USERPROFILE%\.hvctl\config.yaml` に `vms` と `stacks` をまとめる案を検討した。最終的には、`vms` と `stacks` は役割と編集頻度が異なるため、`vms.yaml` と `stacks.yaml` に分ける方針を採用した。

### 1 ファイル 1 Stack 形式

Kubernetes 風の `kind: Stack` 形式も検討した。複数ファイル読み込み順、同名 stack 衝突、multi-document YAML、将来の kind 増加などの論点が増えるため、v0.1 では採用しなかった。

### stack node から `vms.yaml` alias を参照する方式

`stacks.yaml` の node が `vms.yaml` の alias を参照する案を検討した。名前解決の段数が増えるため、v0.1 では node が `vmName` を直接持つ方式を採用した。

### `--stack` / `-s` による node 指定

`hvctl ssh --stack k8s cp1` のような明示指定も検討した。日常操作の短さと target 解決の一貫性を優先し、v0.1 では `<stack>/<node>` のみを採用した。

### `get vm` に IP を表示する

`get vm` に IP を含める案を検討した。全 VM の IP 取得は重くなる可能性があるため、`get vm` では IP を表示せず、`ip vm` と `status stack` に寄せる方針を採用した。

### stack 操作の並列実行

`start stack` / `stop stack` を並列実行する案を検討した。失敗時の扱いと暗黙の依存順が複雑になるため、v0.1 では逐次実行を採用した。

### `dependsOn`

stack node 間の依存関係を設定に持つ案を検討した。設計が大きくなるため、v0.1 では採用しなかった。順序は YAML の `nodes` 定義順で表現する。

### `restart vm` / `restart stack`

日常操作として候補に挙がったが、stop 後に start するタイミング、wait、失敗時挙動を決める必要があるため、v0.1 では採用しなかった。

### password 認証対応

SSH password を `hvctl` が扱う案は採用しなかった。v0.1 では `ssh.exe` に認証を任せ、`hvctl` は password、passphrase、agent、known_hosts を扱わない。

### `pwsh`

PowerShell 7 の `pwsh` も検討したが、Windows 標準環境と Hyper-V module との相性を優先し、v0.1 では `powershell.exe` を採用した。

### Cocona

C# CLI framework として Cocona も検討した。書き味は軽いが、リポジトリが archived / read-only になっているため、v0.1 では `System.CommandLine` を採用した。

### 手書き table のみ

JSON 出力を後回しにする案もあった。スクリプト利用と構造化された Application 戻り値を活かすため、v0.1 から `--output table|json` を採用した。

### single quote escape による PowerShell 引数渡し

VM 名などを single quote escape して PowerShell に埋め込む案を検討した。各所でエスケープ漏れが起きるリスクを避けるため、Base64 JSON payload を採用した。
