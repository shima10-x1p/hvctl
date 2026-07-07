# 0001: Define hvctl v0.1 Scope

## Status

Accepted

## Context

`hvctl` is intended to grow into a CLI that can operate major Hyper-V features where practical. The planned phases are:

- Phase 1: VM operations.
- Phase 2: Stack operations.
- Phase 3: Network.
- Phase 4: Storage.
- Phase 5: Checkpoint.
- Phase 6: VM setting changes.
- Phase 7: Creation commands.
- Phase 8: Declarative management.

An earlier MVP draft included both single-VM operations and stack operations. During v0.1 design, we decided that stack support should move to Phase 2 so v0.1 can establish a clean command model, config model, error model, and architecture around single-VM operations first.

A key design concern is whether `hvctl` should keep a master config that represents desired Hyper-V state. A master config would introduce drift, diff, reconcile, partial apply, and manual-change semantics. Those concerns belong to declarative management in Phase 8, not v0.1.

## Decision

v0.1 is Phase 1 and includes only single-VM operations:

```txt
hvctl get vm
hvctl describe vm <target>
hvctl start vm <target>
hvctl stop vm <target>
hvctl stop vm <target> --force
hvctl ip vm <target>
hvctl ssh <target>
```

Stack operations are explicitly deferred to Phase 2.

Hyper-V is the source of truth for VM state and VM settings.

`vms.yaml` is not a master config. It is a local registry for alias and SSH information only:

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

`vms.yaml` contains no desired VM settings such as memory, processor count, firmware, disk, switch, or generation.

`get` and `describe` never update config.

`get vm` lists Hyper-V VMs and joins aliases from config when possible. Missing config is allowed. Invalid config is an error.

`describe`, `start`, `stop`, `ip`, and `ssh` resolve targets through alias first, then real Hyper-V VM name.

`ssh` remains `hvctl ssh <target>` rather than `hvctl ssh vm <target>` because it is a daily connection shortcut, not a resource inspection command.

v0.1 supports table and JSON output for non-SSH commands. Default output is table. JSON properties are camelCase. Errors are always written to stderr as human-readable messages.

Exit codes are:

```txt
0: Success
1: Runtime error
2: Command-line argument error
3: Config file error
```

The architecture uses ports and adapters from v0.1:

- Console is an inbound adapter.
- Hyper-V PowerShell access is an outbound adapter behind `IHyperVClient`.
- YAML config loading is an outbound adapter behind `IVmConfigRepository`.
- `ssh.exe` launching is an outbound adapter behind `ISshLauncher`.
- User profile lookup is behind `IUserProfileProvider`.
- Application/Core does not depend on PowerShell, YamlDotNet, JsonSchema.Net, System.CommandLine, `ProcessStartInfo`, or console IO.

PowerShell execution remains isolated in Infrastructure and uses:

```txt
powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand <scriptBase64>
```

User-provided values are passed to PowerShell through a Base64 JSON payload rather than direct string interpolation.

## Consequences

v0.1 is smaller than the original MVP draft, but the first implementation can establish the core boundaries without stack complexity.

Because Hyper-V is the source of truth, `hvctl` avoids reconcile and drift semantics in v0.1. This keeps `get` and `describe` read-only and predictable.

Because config is only an alias/SSH registry, config validation remains strict without becoming responsible for validating desired Hyper-V state.

Because missing config is allowed, `hvctl` remains useful immediately for real VM names:

```txt
hvctl get vm
hvctl describe vm <real-vm-name>
hvctl start vm <real-vm-name>
hvctl stop vm <real-vm-name>
hvctl ip vm <real-vm-name>
```

Because invalid config is an error, users are not left wondering why aliases silently disappeared from output.

Because `stop` never falls back to force, users must explicitly choose power-off behavior with `--force`.

Because `start` and `stop` do not wait, v0.1 avoids timeout and polling semantics. Commands report the state observed immediately after the operation.

Because the CLI is only an adapter, future Web API or GUI entry points can reuse the Application/Core layer.

## Alternatives Considered

### Keep Stack in v0.1

The original MVP included stack commands. This was rejected for v0.1 because stack ordering, grouped failures, aliases, node references, and multi-VM output would add a second design axis before the single-VM model is proven.

Stack support is deferred to Phase 2.

### Treat vms.yaml as a Master Config

This was rejected because it would turn v0.1 into partial desired-state management. Desired VM state raises questions about drift detection, manual changes, apply semantics, partial failures, and reconcile behavior.

Those concerns are deferred to Phase 8.

### Update Config During get/describe

This was rejected because read commands should not mutate local files. Automatic updates would make command behavior surprising and could overwrite user-edited config.

### Config-Free SSH

Allowing `ssh` without config would require guessing or accepting CLI flags for user, identity, and other SSH options. v0.1 keeps SSH simple: `ssh.user` comes from config, while host may be auto-resolved from Hyper-V IP addresses.

### `hvctl ssh vm <target>`

This was rejected for v0.1 in favor of the shorter `hvctl ssh <target>`. SSH is treated as a high-frequency connection shortcut.

### YAML Output

YAML output was deferred. v0.1 supports table and JSON only.

### Structured JSON Errors

Structured JSON errors were deferred. Errors always go to stderr as human-readable messages regardless of `--output`.

### Automatic Graceful-to-Force Stop Fallback

This was rejected because forced turn off is a strong operation. Users must explicitly request it with `--force`.

### Waiting for Start/Stop Completion

`--wait`, timeout, and retry were deferred. v0.1 reports the immediate post-operation state.

### PowerShell 7 `pwsh`

`pwsh` was not selected for v0.1. Windows PowerShell is used for compatibility with typical Hyper-V management environments.
