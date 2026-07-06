# hvctl MVP Spec

## 目的

`hvctl` は、Hyper-V 上の既存 VM に対する日常操作を、安全に、再現可能に、短いコマンドで実行するための Windows 向け CLI ツールである。

Hyper-V の全機能を抽象化することは目的ではない。v0.1 では、既存 VM の一覧確認、起動、停止、IP 確認、SSH 接続、stack 単位の起動・停止に限定する。

## 背景

Hyper-V の VM を PowerShell や Hyper-V マネージャーで手作業管理すると、VM 名が長い、複数 VM の起動・停止が面倒、SSH 接続先を毎回確認する必要がある、という課題がある。

`hvctl` は Kubernetes の `kubectl` の操作感を一部参考にするが、Kubernetes 互換や宣言的 apply の再実装は行わない。設定ファイルは Hyper-V の望ましい状態を宣言する manifest ではなく、既存 VM を `hvctl` の短い名前や stack として扱うためのローカル台帳である。

## スコープ

- Hyper-V 上の全 VM 一覧を表示する。
- VM を起動する。
- VM を graceful shutdown で停止する。
- `--force` 指定時のみ VM を強制停止する。
- VM の IP アドレスを表示する。
- `vms.yaml` で単体 VM alias を定義する。
- `stacks.yaml` で stack と node を定義する。
- stack 単位で複数 VM を起動・停止する。
- stack 内の node を `<stack>/<node>` で参照する。
- SSH 接続先を解決し、`ssh.exe` を起動する。
- table 出力と JSON 出力を提供する。
- 設定ファイルを JSON Schema と C# semantic validation で検証する。

## 非スコープ

- VM の新規作成。
- VM の削除。
- VHDX の作成・変更。
- ISO のマウント。
- 仮想スイッチの作成・変更。
- checkpoint / snapshot 管理。
- cloud-init 対応。
- 宣言的な `apply -f`。
- 設定と実 VM の reconcile / drift 検出 / sync。
- WebAPI。
- WinUI デスクトップアプリ。
- GUI。
- 常駐サービス。
- Kubernetes CRD 的な仕組み。
- Hyper-V の全機能の抽象化。
- restart コマンド。
- dependency graph / `dependsOn`。
- 並列 stack 操作。
- `--continue-on-error`。
- SSH password の保存、入力、仲介。
- SSH passphrase、agent、known_hosts の管理。
- `sshCommand` の設定。
- current directory からの config 自動探索。
- 複数 config merge。
- `config.d`。
- `HVCTL_CONFIG`。
- `--wait`、timeout、retry。
- YAML 出力、wide 出力、custom columns、jsonpath。
- ログ基盤、`--verbose`、`--debug`。

## 用語

- VM: Hyper-V 上の実 VM。実 VM 名は `vmName` と呼ぶ。
- alias: `vms.yaml` で定義する単体 VM の短い名前。
- stack: 複数 VM を束ねる論理グループ。
- node: stack 内の VM 別名。Hyper-V の実 VM 名ではない。
- target: CLI 引数として渡される VM 参照。alias、Hyper-V VM 名、または `<stack>/<node>`。
- `<stack>/<node>`: stack 内 node の参照記法。`/` を含む target は stack/node として解釈する。
- config dir: `vms.yaml` と `stacks.yaml` を置くディレクトリ。
- role: node の短い表示用ラベル。v0.1 ではロジックに使わない。

## 機能仕様

### 共通 CLI オプション

- `--config-dir <path>`
  - 設定ディレクトリを指定する。
  - 省略時は `%USERPROFILE%\.hvctl` を使う。
- `-o, --output <table|json>`
  - 出力形式を指定する。
  - 省略時は `table`。

### target 解決

`vm` 操作と `ssh` 操作の target 解決は以下とする。

- target に `/` がある場合:
  - `stacks.yaml` の `<stack>/<node>` として解釈する。
  - 解決結果は node の `vmName`。
- target に `/` がない場合:
  - `vms.yaml` の `alias` を case-insensitive に検索する。
  - alias がなければ target を Hyper-V VM 名として扱う。

`hvctl ssh cp1` のような、stack 名なしの node グローバル解決は行わない。

### `hvctl get vm`

Hyper-V 上の全 VM を表示する。設定ファイルが存在しなくても動作する。

表示順は VM 名昇順、case-insensitive とする。

table 出力の列:

```txt
VM
STATE
ALIAS
STACK
UPTIME
CPU
MEMORY
```

- `VM`: Hyper-V の実 VM 名。
- `STATE`: Hyper-V の状態表示文字列。
- `ALIAS`: 同一 `vmName` を参照する alias。複数ある場合はカンマ区切り。
- `STACK`: 同一 `vmName` を参照する `<stack>/<node>`。複数ある場合はカンマ区切り。
- `UPTIME`: 起動中 VM の稼働時間。値がない場合は `-`。
- `CPU`: CPU 使用率。値がない場合は `-`。
- `MEMORY`: 現在割り当てメモリ。値がない場合は `-`。

`get vm` では IP アドレスを表示しない。

### `hvctl start vm <target>`

target を解決し、対象 VM を起動する。

skip 判定:

- `Running`, `Starting`, `Resuming` は `skipped`。
- それ以外は `Start-VM` を実行する。

操作後に 1 回だけ VM 状態を再取得し、結果に含める。目的状態になるまでの wait、retry、timeout は行わない。

### `hvctl stop vm <target>`

target を解決し、対象 VM を停止する。

skip 判定:

- `Off` は `skipped`。
- それ以外は stop を実行する。
- `Saved` は `skipped` 扱いにしない。

通常 stop:

```powershell
Stop-VM -Name <name> -Shutdown -Confirm:$false
```

強制 stop:

```powershell
Stop-VM -Name <name> -TurnOff -Confirm:$false
```

強制 stop は `--force` 指定時のみ行う。通常 stop が失敗しても自動で force には切り替えない。

操作後に 1 回だけ VM 状態を再取得し、結果に含める。目的状態になるまでの wait、retry、timeout は行わない。

### `hvctl ip vm <target>`

target を解決し、対象 VM の IP アドレスを表示する。

IP 取得元:

```powershell
Get-VMNetworkAdapter -VMName <name>
```

`IPAddresses` に含まれる IP をすべて表示する。表示順は IPv4、IPv6 の順とする。

v0.1 では link-local IPv6、APIPA、private/public の除外や分類は行わない。

### `hvctl ssh <target>`

target を解決し、SSH 接続先を作って `ssh.exe` を起動する。

解決ルール:

- `ssh.user` は必須。
- `ssh.host` があればそれを使う。
- `ssh.host` がなければ Hyper-V から IP を取得する。
- host 自動解決時は、IPv4 があれば最初の IPv4、なければ最初の IPv6 を使う。
- `ssh.port` 省略時は `22`。
- `ssh.identityFile` は省略可。
- `identityFile` の `~` は `%USERPROFILE%` に展開する。

`ssh.exe` は PATH 解決に任せる。

`hvctl` は `ssh.exe` の stdin/stdout/stderr を継承し、`ssh.exe` の exit code をそのまま返す。

### `hvctl get stack`

設定ファイルに定義された stack 一覧を表示する。

表示順は stack 名昇順、case-insensitive とする。

table 出力の列:

```txt
NAME
NODES
```

### `hvctl status stack <stack-name>`

指定 stack の node 詳細を表示する。表示順は `stacks.yaml` の `nodes` 定義順とする。

table 出力の列:

```txt
NODE
VM
ROLE
STATE
IP
SSH
```

- `IP`: Hyper-V から取れた最初の IPv4。なければ最初の IPv6。なければ `-`。
- `SSH`: `user@host:port`。host 省略時は `user@<auto>:port`。

### `hvctl start stack <stack-name>`

指定 stack の node を定義順に逐次起動する。

各 node は `start vm <stack>/<node>` 相当の skip 判定と操作を行う。

途中で失敗した場合、それ以降の node は実行せず、結果に `not-run` として含める。

### `hvctl stop stack <stack-name>`

指定 stack の node を定義の逆順に逐次停止する。

各 node は `stop vm <stack>/<node>` 相当の skip 判定と操作を行う。

途中で失敗した場合、それ以降の node は実行せず、結果に `not-run` として含める。

### stack 操作結果

stack 操作の結果種別:

```txt
changed
skipped
failed
not-run
```

`skipped` は失敗ではない。`failed` が 1 件でもあれば exit code は `1` とする。

## 設定仕様

### 設定ディレクトリ

既定:

```txt
%USERPROFILE%\.hvctl
```

読み込むファイル:

```txt
vms.yaml
stacks.yaml
```

`--config-dir <path>` で任意の設定ディレクトリを指定できる。

`vms.yaml` と `stacks.yaml` は片方だけ存在しても有効とする。両方ない場合は config なしとして扱う。

### `vms.yaml`

```yaml
schemaVersion: hvctl/v1
vms:
  - alias: ubuntu
    vmName: lab-ubuntu-2404
    ssh:
      user: ubuntu
      host: 192.168.50.20
      port: 22
      identityFile: ~/.ssh/lab_ed25519
```

### `stacks.yaml`

```yaml
schemaVersion: hvctl/v1
stacks:
  - name: k8s
    nodes:
      - name: cp1
        vmName: lab-k8s-mito
        role: control-plane
        ssh:
          user: ubuntu
          host: 192.168.50.11
          port: 22
          identityFile: ~/.ssh/lab_ed25519

      - name: w1
        vmName: lab-k8s-sango
        role: worker
        ssh:
          user: ubuntu
```

### 設定項目

- `schemaVersion`
  - 必須。
  - `hvctl/v1` のみ許可。
- `vms[].alias`
  - 必須。
  - VM alias。
- `vms[].vmName`
  - 必須。
  - Hyper-V の実 VM 名。
- `vms[].ssh`
  - 任意。
- `stacks[].name`
  - 必須。
  - stack 名。
- `stacks[].nodes`
  - 必須。
- `nodes[].name`
  - 必須。
  - stack 内 node 名。
- `nodes[].vmName`
  - 必須。
  - Hyper-V の実 VM 名。
- `nodes[].role`
  - 任意。
  - 短い表示用ラベル。ロジックには使わない。
- `nodes[].ssh`
  - 任意。
- `ssh.user`
  - 必須。
- `ssh.host`
  - 任意。
- `ssh.port`
  - 任意。省略時は `22`。
- `ssh.identityFile`
  - 任意。

### 名前ルール

`alias`、`stack.name`、`node.name` は以下を満たす必要がある。

```txt
^[A-Za-z0-9_.-]+$
```

解決と重複チェックは case-insensitive とする。表示は設定ファイルに書かれた表記を維持する。

`vmName` は既存 Hyper-V VM 名なので、空でないことだけ検証する。

### 重複ルール

エラーにするもの:

- `vms[].alias` の重複。
- `stacks[].name` の重複。
- 同一 stack 内の `nodes[].name` の重複。

許可するもの:

- vm alias と stack name の重複。
- 異なる stack 間の同じ node name。
- 同じ `vmName` の複数登録。

### 設定検証

YAML は `YamlDotNet` で読み込む。

設定ファイルは `JsonSchema.Net` による JSON Schema validation を行う。JSON Schema は Infrastructure プロジェクト内に `.json` として置き、実行時は embedded resource から読む。

JSON Schema で検証するもの:

- `schemaVersion` 必須。
- `schemaVersion` が `hvctl/v1` であること。
- 必須項目。
- 型。
- 未知フィールド。
- 名前の pattern。
- `ssh.port` の範囲。

C# semantic validation で検証するもの:

- case-insensitive な alias 重複。
- case-insensitive な stack name 重複。
- case-insensitive な同一 stack 内 node name 重複。

未知フィールドは v0.1 では config error とする。

### 外部依存

- Windows。
- Hyper-V 管理権限。
- `powershell.exe`。
- Hyper-V PowerShell module。
- SSH 機能を使う場合は PATH から解決できる `ssh.exe`。

### 実装技術

- Target Framework: `net10.0`。
- CLI parser: `System.CommandLine`。
- YAML: `YamlDotNet`。
- JSON Schema validation: `JsonSchema.Net`。
- DI: `Microsoft.Extensions.DependencyInjection`。
- Test framework: `xUnit`。

## エラー仕様

### exit code

- `0`: 成功。`skipped` のみでも成功。
- `1`: 実行時エラー。
- `2`: コマンドライン引数エラー。`System.CommandLine` に任せる。
- `3`: 設定ファイルエラー。

### stdout / stderr

- stdout は table / json の通常出力のみ。
- stderr はエラーメッセージと詳細。

### 想定される失敗

- VM が見つからない。
- stack が見つからない。
- node が見つからない。
- `ssh.user` が未設定。
- `ssh.host` がなく、Hyper-V から IP が取得できない。
- PowerShell 実行に失敗した。
- `ssh.exe` の起動に失敗した。
- YAML parse error。
- JSON Schema validation error。
- semantic validation error。
- 未対応の `schemaVersion`。

PowerShell 失敗時は、`hvctl` の文脈つきメッセージを表示し、PowerShell stderr も詳細として表示する。

### Result と例外

Core/Application では想定内の失敗を `Result<T>` で表す。

`Result` の error code は enum とする。

例:

```txt
VmNotFound
StackNotFound
NodeNotFound
MissingSshUser
MissingSshHost
ConfigInvalid
HyperVCommandFailed
SshLaunchFailed
```

予期しない異常は例外として扱う。

## 受け入れ条件

- `%USERPROFILE%\.hvctl` が存在しない状態で `hvctl get vm` を実行すると、Hyper-V 上の全 VM が VM 名昇順で表示され、exit code が `0` になる。
- `%USERPROFILE%\.hvctl` が存在しない状態で `hvctl start vm <real-vm-name>` を実行すると、`<real-vm-name>` を Hyper-V VM 名として扱う。
- `vms.yaml` に `alias: ubuntu` と `vmName: lab-ubuntu-2404` がある状態で `hvctl start vm ubuntu` を実行すると、`lab-ubuntu-2404` に対して起動処理を行う。
- `stacks.yaml` に `k8s/cp1` がある状態で `hvctl start vm k8s/cp1` を実行すると、`cp1` の `vmName` に対して起動処理を行う。
- `hvctl start vm <target>` 実行時、対象 VM の状態が `Running` の場合、結果が `skipped` になり、Hyper-V の start 操作は呼ばれない。
- `hvctl stop vm <target>` 実行時、対象 VM の状態が `Off` の場合、結果が `skipped` になり、Hyper-V の stop 操作は呼ばれない。
- `hvctl stop vm <target>` 実行時、対象 VM の状態が `Saved` の場合、`skipped` にはならない。
- `hvctl stop vm <target>` は通常 stop で `Stop-VM -Shutdown -Confirm:$false` 相当を呼ぶ。
- `hvctl stop vm <target> --force` は `Stop-VM -TurnOff -Confirm:$false` 相当を呼ぶ。
- `hvctl ip vm <target>` は Hyper-V から取得できた IP をすべて表示し、IPv4 を IPv6 より先に表示する。
- `hvctl ssh <target>` は `ssh.user`、解決済み host、port、identityFile から `ssh.exe` を起動し、`ssh.exe` の exit code をそのまま返す。
- `ssh.identityFile` が `~/.ssh/key` の場合、`~` が `%USERPROFILE%` に展開されて `ssh.exe` に渡される。
- `hvctl get stack` は stack 名昇順で `NAME` と `NODES` を表示する。
- `hvctl status stack k8s` は `stacks.yaml` の node 定義順で `NODE`, `VM`, `ROLE`, `STATE`, `IP`, `SSH` を表示する。
- `hvctl start stack k8s` は `nodes` 定義順に逐次実行する。
- `hvctl stop stack k8s` は `nodes` 逆順に逐次実行する。
- stack 操作で途中の node が失敗した場合、それ以降の node は実行されず、結果に `not-run` として含まれ、exit code が `1` になる。
- `hvctl get vm -o json` は JSON を stdout に出力する。
- `hvctl get vm -o table` は table を stdout に出力する。
- `vms.yaml` に `schemaVersion` がない場合、設定ファイルエラーになり、exit code が `3` になる。
- `vms.yaml` の `schemaVersion` が `hvctl/v1` 以外の場合、設定ファイルエラーになり、exit code が `3` になる。
- `vms.yaml` に未知フィールドがある場合、設定ファイルエラーになり、exit code が `3` になる。
- `vms.yaml` に case-insensitive で重複する alias がある場合、設定ファイルエラーになり、exit code が `3` になる。
- `stacks.yaml` に case-insensitive で重複する stack name がある場合、設定ファイルエラーになり、exit code が `3` になる。
- 同一 stack 内に case-insensitive で重複する node name がある場合、設定ファイルエラーになり、exit code が `3` になる。
- 同じ `vmName` が複数 alias または stack node から参照される場合、設定ファイルエラーにならず、`get vm` の `ALIAS` / `STACK` にカンマ区切りで表示される。
- `vms.yaml` だけが存在する場合、vm alias は使えるが stack 操作は stack 未定義エラーになる。
- `stacks.yaml` だけが存在する場合、stack 操作は使えるが vm alias は未定義扱いになる。
- PowerShell に渡すユーザー入力値は Base64 JSON payload 経由で渡され、PowerShell スクリプトへ直接文字列埋め込みされない。
- PowerShell 実行は `powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand <scriptBase64>` で行われる。
- PowerShell の JSON 出力は常に配列として返され、C# 側では list として deserialize される。

## 確認方法

### 自動テスト

- Core の target 解決テスト。
- Core の start/stop skip 判定テスト。
- stack 起動順、停止順、途中失敗時の `not-run` テスト。
- `Result<T>` の error code mapping テスト。
- `vms.yaml` / `stacks.yaml` の JSON Schema validation テスト。
- 未知フィールド、schemaVersion 未指定、schemaVersion 不一致の validation テスト。
- alias、stack、node の case-insensitive 重複 validation テスト。
- `identityFile` の `~` 展開テスト。
- PowerShellRunner の Base64 JSON payload 生成テスト。
- PowerShellRunner の `-EncodedCommand` 生成テスト。

### 手動確認

- Hyper-V 管理権限を持つ Windows で `hvctl get vm` を実行する。
- 実 VM 名を指定して `start vm` / `stop vm` / `ip vm` を実行する。
- `vms.yaml` を作成し、alias 指定で `start vm` / `stop vm` / `ssh` を実行する。
- `stacks.yaml` を作成し、`get stack` / `status stack` / `start stack` / `stop stack` を実行する。
- `-o json` で JSON 出力を確認する。
- 壊れた YAML と schema 違反 YAML を使い、exit code `3` と stderr の内容を確認する。

## 未決定事項

- NuGet package の正確なバージョン。
- `System.CommandLine` の具体的な API 使用形態。
- JSON Schema の `$schema` バージョン。
- table 出力の具体的な桁幅、折り返し、長い値の扱い。
- JSON 出力の厳密な property 名。
- `VmInfo` や operation result の最終 C# namespace / class 名。
- `ConfigLoadResult` の最終 C# 形。
- PowerShell DTO の正確な property 名と日時・メモリ単位の変換方法。
- `ssh.host` 自動解決時に IP が複数ある場合の JSON 出力形。
- README の最終構成。
