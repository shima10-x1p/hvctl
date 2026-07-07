# hvctl
Command-line tools for managing Hyper-V.

## Solution 構成

- `src/HvCtl.Core`: Application/Domain/Ports（inbound/outbound から独立した中心層）
- `src/HvCtl.Infrastructure`: Config/HyperV/Ssh（outbound adapter）
- `src/HvCtl.Console`: Commands/Formatting（inbound adapter, CLI 実行可能プロジェクト）
- `tests/HvCtl.Core.Tests`, `tests/HvCtl.Infrastructure.Tests`, `tests/HvCtl.Console.Tests`: 対応する xUnit テストプロジェクト

```
dotnet restore
dotnet build
dotnet test
```
