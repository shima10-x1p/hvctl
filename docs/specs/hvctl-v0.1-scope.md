# hvctl v0.1 Scope

## Goal

`hvctl` v0.1 is a Windows CLI for day-to-day operations on existing Hyper-V virtual machines.

The long-term goal is to make major Hyper-V operations available from `hvctl` where practical. v0.1 is Phase 1 of that plan and focuses only on single-VM operations:

- `get`
- `describe`
- `start`
- `stop`
- `ip`
- `ssh`

v0.1 does not manage desired VM state. Hyper-V is the source of truth. The local config file is only a small registry for aliases and SSH settings.

## Phase Plan

- Phase 1: VM operations: `get`, `describe`, `start`, `stop`, `ip`, `ssh`.
- Phase 2: Stack operations: multiple VM start/stop, aliases, SSH connection helpers.
- Phase 3: Network: switch list, VM switch connection, adapter information.
- Phase 4: Storage: disk list, VHDX attachment, DVD/ISO status.
- Phase 5: Checkpoint: create, list, restore, delete.
- Phase 6: VM settings: memory, processor, firmware, boot order.
- Phase 7: Creation commands: create VM, create disk, connect switch, and related operations.
- Phase 8: Declarative management: `schemaVersion: hvctl/v1`, `kind: VirtualMachine`, `Stack`, `Switch`, `diff`, `plan`, `apply`.

## Non-Goals

v0.1 does not include:

- Stack operations.
- Multiple VM operations.
- VM creation.
- VM deletion.
- VM setting changes.
- VHDX creation or modification.
- ISO mount or unmount.
- Virtual switch creation or modification.
- Checkpoint management.
- Declarative `apply`.
- Diff, plan, reconcile, drift detection, or sync.
- A master config that describes desired VM state.
- Automatic config updates from `get` or `describe`.
- Web API.
- GUI.
- Background service.
- `restart`.
- `--wait`, timeout, or retry.
- YAML output.
- Structured JSON errors.
- SSH password, passphrase, agent, or `known_hosts` management.

## Source of Truth

Hyper-V is the source of truth for VM state and VM settings.

`vms.yaml` is not a master config. It is a local registry for:

- Short aliases.
- The real Hyper-V VM name.
- SSH connection settings.

`get` and `describe` commands never update `vms.yaml`.

VM details such as memory, processor count, generation, switch connection, adapter information, and IP addresses are read from Hyper-V when needed.

## Commands

v0.1 provides these commands:

```txt
hvctl get vm
hvctl describe vm <target>
hvctl start vm <target>
hvctl stop vm <target>
hvctl stop vm <target> --force
hvctl ip vm <target>
hvctl ssh <target>
```

`ssh` intentionally does not include `vm` in the command path. It is treated as a daily shortcut for connecting to the resolved target.

## Common Options

```txt
--config-dir <path>
-o, --output <table|json>
```

Default output is `table`.

`--output` applies to:

- `get vm`
- `describe vm`
- `start vm`
- `stop vm`
- `ip vm`

`ssh` does not support `--output`; it launches `ssh.exe` and returns its exit code.

If `--config-dir` is omitted, the config adapter resolves the default directory:

```txt
%USERPROFILE%\.hvctl
```

The console layer passes an explicit path or `null`; it does not resolve the default itself.

## Config File

Phase 1 reads only:

```txt
%USERPROFILE%\.hvctl\vms.yaml
```

or, with `--config-dir`:

```txt
<config-dir>\vms.yaml
```

Example:

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

Allowed fields:

- `schemaVersion`
- `vms[].alias`
- `vms[].vmName`
- `vms[].ssh.user`
- `vms[].ssh.host`
- `vms[].ssh.port`
- `vms[].ssh.identityFile`

`vms[].ssh` is optional.

If `ssh` is present, `ssh.user` is required.

`ssh.host`, `ssh.port`, and `ssh.identityFile` are optional.

`ssh.port` defaults to `22`.

`identityFile` may start with `~`. v0.1 expands `~` to `%USERPROFILE%` before launching `ssh.exe`. v0.1 does not check whether the identity file exists.

VM configuration fields such as `memory`, `processor`, `switch`, `disk`, and `generation` are not allowed in `vms.yaml`.

## Config Validation

Validation is performed in two layers.

JSON Schema validation checks:

- `schemaVersion` is required.
- `schemaVersion` must be `hvctl/v1`.
- Required fields.
- Field types.
- Unknown fields.
- Alias pattern.
- `ssh.port` range.

C# semantic validation checks:

- Case-insensitive duplicate aliases.

`alias` must match:

```txt
^[A-Za-z0-9_.-]+$
```

`vmName` must be non-empty. It has no character restriction because it is an existing Hyper-V VM name.

If `vms.yaml` does not exist, commands run with no config.

If `vms.yaml` exists but is invalid, all commands fail with a config error and exit code `3`.

## Target Resolution

A `<target>` is resolved as follows:

1. If `vms.yaml` contains a case-insensitive alias matching `<target>`, resolve to that entry's `vmName`.
2. Otherwise, treat `<target>` as a real Hyper-V VM name.

If an alias points to a missing Hyper-V VM, config validation still succeeds.

Missing VM behavior:

- `get vm`: missing aliases are ignored.
- `describe vm`, `start vm`, `stop vm`, `ip vm`, `ssh`: fail with `VM not found` and exit code `1`.

## `get vm`

`get vm` lists VMs from Hyper-V. Hyper-V is the primary data source; config aliases are joined onto the Hyper-V result.

If no config exists, `ALIAS` is `-` for every row.

If config contains an alias for a VM that does not exist in Hyper-V, that alias is not shown.

Default table columns:

```txt
VM
STATE
ALIAS
UPTIME
CPU
MEMORY
```

`get vm` does not fetch or display IP addresses.

Rows are sorted by VM name, case-insensitive.

JSON output is an array:

```json
[
  {
    "vm": "lab-ubuntu-2404",
    "state": "Running",
    "alias": "ubuntu",
    "uptime": "01:23:45",
    "cpuUsagePercent": 2,
    "memoryAssignedBytes": 2147483648
  }
]
```

## `describe vm <target>`

`describe vm` displays detailed information for one VM.

VM state and VM settings are read from Hyper-V. Alias and SSH settings are read from config.

Expected table-style content:

```txt
Name:        lab-ubuntu-2404
Alias:       ubuntu
State:       Running
Uptime:      01:23:45
CPU:         2 %
Memory:      2048 MB
Generation:  2
Version:     12.0

Network:
  Adapter:   Network Adapter
  Switch:    Default Switch
  MAC:       00155D...
  IPs:       172.20.10.5, fe80::...

SSH:
  User:      ubuntu
  Host:      dev.local
  Port:      22
  Identity:  C:\Users\shima\.ssh\lab_ed25519
```

Network information is intentionally limited in v0.1 to adapter name, switch name, MAC address, and IP addresses. Detailed network inspection belongs to Phase 3.

The Network section always reflects Hyper-V. The SSH section reflects the resolved SSH configuration.

If `ssh.host` is configured, it is displayed as the SSH host. Hyper-V IP addresses are still shown in the Network section.

If `ssh.host` is not configured, the SSH host is auto-resolved from Hyper-V IP addresses when possible.

If no SSH config exists for the VM, the SSH section reports that SSH is not configured.

## `start vm <target>`

`start vm` resolves the target, reads the current VM state, and starts the VM unless it is already running or transitioning toward running.

Skip states:

- `Running`
- `Starting`
- `Resuming`

All other states call `Start-VM`.

After the operation, `hvctl` reads the VM state one more time. It does not wait, retry, or poll for the desired state.

Table output:

```txt
VM                 ACTION   BEFORE   AFTER
lab-ubuntu-2404    changed  Off      Starting
```

Actions:

- `changed`
- `skipped`

JSON output is an object:

```json
{
  "vm": "lab-ubuntu-2404",
  "action": "changed",
  "beforeState": "Off",
  "afterState": "Starting"
}
```

## `stop vm <target>`

`stop vm` resolves the target, reads the current VM state, and stops the VM unless it is already `Off`.

Default stop is graceful shutdown:

```powershell
Stop-VM -Name <name> -Shutdown -Confirm:$false
```

Forced stop is available only with `--force`:

```powershell
Stop-VM -Name <name> -TurnOff -Confirm:$false
```

`hvctl` never automatically falls back from graceful shutdown to force stop.

If graceful shutdown fails, the command fails with exit code `1` and a human-readable hint to retry with `--force`.

Skip states:

- `Off`

`Saved` is not skipped.

After the operation, `hvctl` reads the VM state one more time. It does not wait, retry, or poll for the desired state.

Table output:

```txt
VM                 ACTION   BEFORE   AFTER
lab-ubuntu-2404    changed  Running  Stopping
```

JSON output is an object:

```json
{
  "vm": "lab-ubuntu-2404",
  "action": "changed",
  "beforeState": "Running",
  "afterState": "Stopping"
}
```

## `ip vm <target>`

`ip vm` resolves the target and displays all IP addresses reported by Hyper-V.

IP source:

```powershell
Get-VMNetworkAdapter -VMName <name>
```

All addresses are shown. v0.1 does not filter:

- Link-local IPv6.
- APIPA.
- Private addresses.
- Public addresses.

Display order:

1. IPv4.
2. IPv6.

Table output:

```txt
IP
172.20.10.5
fe80::215:5dff:fe...
```

JSON output is an object:

```json
{
  "vm": "lab-ubuntu-2404",
  "ipAddresses": [
    "172.20.10.5",
    "fe80::215:5dff:fe..."
  ]
}
```

## `ssh <target>`

`ssh` resolves the target and launches `ssh.exe`.

Resolution:

1. Resolve target to a VM.
2. Find SSH config for the resolved VM.
3. Require `ssh.user`.
4. If `ssh.host` is configured, use it.
5. If `ssh.host` is not configured, read Hyper-V IP addresses and use the first IPv4 address, or the first IPv6 address if no IPv4 exists.
6. Default `ssh.port` to `22`.
7. Expand `identityFile` `~` to `%USERPROFILE%`.
8. Launch `ssh.exe`.

`ssh` does not special-case VM state. It attempts host resolution regardless of whether the VM is `Running` or `Off`.

If no host can be resolved:

```txt
error: SSH host is not configured and no IP address was found for VM 'lab-ubuntu-2404'
hint: set ssh.host in vms.yaml or start the VM and retry
```

`ssh.exe` is resolved through `PATH`.

`hvctl` inherits stdin, stdout, and stderr for `ssh.exe`.

`hvctl ssh` returns the exit code from `ssh.exe`.

`hvctl` does not manage:

- Passwords.
- Passphrases.
- SSH agent.
- `known_hosts`.
- Host key policy.

## Output Rules

Normal command output is written to stdout.

Errors are always written to stderr as human-readable messages, even when `-o json` is specified.

v0.1 does not provide structured JSON errors.

JSON property names are camelCase because JSON output is an external CLI contract, not a .NET object dump.

## Exit Codes

```txt
0: Success
1: Runtime error
2: Command-line argument error
3: Config file error
```

Examples:

- `VM not found`: `1`
- Hyper-V PowerShell failure: `1`
- `ssh.exe` launch failure: `1`
- `ssh.exe` process exit: same exit code as `ssh.exe`
- Unknown option or missing argument: `2`
- YAML parse error: `3`
- JSON Schema validation error: `3`
- Duplicate alias: `3`

## Architecture

v0.1 uses ports and adapters from the beginning.

The CLI is an inbound adapter, not the application core.

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
  Formatting
```

Responsibilities:

```txt
Console adapter:
  System.CommandLine
  Command arguments and options
  stdout/stderr
  table/json formatting
  exit code mapping

Application/Core:
  Use cases
  Target resolution
  start/stop skip decisions
  SSH command resolution
  Result<T> and error codes

Outbound ports:
  IHyperVClient
  IVmConfigRepository
  ISshLauncher
  IUserProfileProvider

Infrastructure adapters:
  PowerShellHyperVClient
  YamlVmConfigRepository
  ProcessSshLauncher
  UserProfileProvider
```

Application/Core must not depend on:

- PowerShell command text.
- `-EncodedCommand`.
- YamlDotNet.
- JsonSchema.Net.
- `ProcessStartInfo`.
- System.CommandLine.
- `Console.WriteLine`.

`ssh` is implemented as an Application use case. The Application resolves the target, SSH config, auto host, port, and identity file path, then calls `ISshLauncher`.

`identityFile` `~` expansion is part of the Application SSH resolution logic. The actual home directory is supplied through `IUserProfileProvider`.

## PowerShell Boundary

Hyper-V access is isolated behind `IHyperVClient`.

Infrastructure uses:

```txt
powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand <scriptBase64>
```

User-provided values are passed to PowerShell as a Base64 JSON payload. They are not directly interpolated into PowerShell script text.

PowerShell output is JSON from `ConvertTo-Json`. C# deserializes that JSON into DTOs.

## Technologies

- Target framework: `net10.0`
- CLI parser: `System.CommandLine`
- YAML: `YamlDotNet`
- JSON Schema validation: `JsonSchema.Net`
- DI: `Microsoft.Extensions.DependencyInjection`
- Test framework: `xUnit`

## Acceptance Criteria

- With no `%USERPROFILE%\.hvctl\vms.yaml`, `hvctl get vm` lists Hyper-V VMs and displays `ALIAS` as `-`.
- With no config, real VM names can be used with `describe`, `start`, `stop`, and `ip`.
- With no config, `ssh` fails because SSH user is not configured.
- If `vms.yaml` exists but is invalid, every command fails with exit code `3`.
- If `vms.yaml` contains `alias: ubuntu` and `vmName: lab-ubuntu-2404`, `hvctl start vm ubuntu` operates on `lab-ubuntu-2404`.
- `get vm` ignores config aliases whose `vmName` does not exist in Hyper-V.
- `describe/start/stop/ip/ssh` fail with `VM not found` when their resolved `vmName` does not exist in Hyper-V.
- `get vm` does not fetch IP addresses.
- `describe vm` shows Hyper-V VM details, limited network details, and SSH resolution details.
- `start vm` skips `Running`, `Starting`, and `Resuming`.
- `start vm` reads VM state once after calling `Start-VM`.
- `stop vm` skips only `Off`.
- `stop vm` does not skip `Saved`.
- `stop vm` uses graceful shutdown by default.
- `stop vm --force` uses forced turn off.
- `stop vm` never automatically falls back to `--force`.
- `stop vm` reads VM state once after calling `Stop-VM`.
- `ip vm` displays all IP addresses, with IPv4 before IPv6.
- `ssh` uses configured `ssh.host` when present.
- `ssh` auto-resolves host from Hyper-V IP addresses when `ssh.host` is absent.
- `ssh` uses first IPv4, then first IPv6, for automatic host resolution.
- `ssh.identityFile` expands leading `~` to `%USERPROFILE%`.
- `ssh.exe` stdin/stdout/stderr are inherited.
- `hvctl ssh` returns the exit code from `ssh.exe`.
- `get vm -o json` returns a JSON array with camelCase properties.
- `describe/start/stop/ip -o json` return JSON objects with camelCase properties.
- Errors always go to stderr as human-readable messages.
- PowerShell user inputs are passed through Base64 JSON payloads.
- PowerShell scripts are executed with `-EncodedCommand`.
