# Insurgency 2014 SourceMod Plugins

Workspace for custom SourceMod plugins used by the Insurgency 2014 game server.

## Layout

```text
new-written-mods/
|-- scripting/              SourcePawn plugin source files
|   |-- include/            Shared/custom include files
|   `-- examples/           Reference code that is not built by default
|-- compiled/               Generated `.smx` plugin binaries
|-- configs/                Plugin configuration files deployed to `addons/sourcemod/configs`
|-- translations/           SourceMod translation phrase files
|-- gamedata/               Game signatures, offsets, and SDKCall data
|-- data/                   Runtime data files used by plugins
|-- cfg/                    Server `.cfg` files and plugin-generated defaults
|-- docs/                   Design notes and plugin documentation
|   `-- plugins/            One Markdown document per plugin
|-- scripts/                Local build, validation, and packaging scripts
|-- tools/                  Local compiler/tooling location (not committed)
`-- packages/               Generated deployment packages (not committed)
```

## Plugin naming

Keep one main source file per plugin directly under `scripting/`:

```text
scripting/ins_admin_tools.sp
scripting/ins_round_manager.sp
scripting/ins_spawn_protection.sp
```

Use a consistent `ins_` prefix so custom plugins are easy to identify on the server. Put reusable SourcePawn code in `scripting/include/`, not in another plugin's main source file.

## Deployment mapping

| Repository path | Server path |
|---|---|
| `compiled/*.smx` | `insurgency/addons/sourcemod/plugins/` |
| `configs/*` | `insurgency/addons/sourcemod/configs/` |
| `translations/*` | `insurgency/addons/sourcemod/translations/` |
| `gamedata/*` | `insurgency/addons/sourcemod/gamedata/` |
| `data/*` | `insurgency/addons/sourcemod/data/` |
| `cfg/*` | `insurgency/cfg/` |

Do not copy `.sp` source files to the live plugins directory. Compile them to `.smx` first.

## Tooling

Place or link a compatible SourceMod toolchain under `tools/sourcemod/`, including `scripting/spcomp.exe` and SourceMod's standard `scripting/include/` directory. Tool binaries are ignored by Git so a particular local installation is not accidentally committed.

