# Arbitration4 Installer

Installs the following additional features for OpenWF:

1. Forces 4 player enemy spawn to **all Non-SP missions**.
2. Forces 4 player count read by the Arbitration Drone spawning logic in `LotusGameRules.lua`.
3. Adds Arbitration node, mission type, and faction controls to the SpaceNinjaServer WebUI. The schedule is loaded from [browse.wf](https://browse.wf/arbys). **This UI is visible only to administrator accounts**.

## Important Limitations

- This tool **Only supports 2026.05.13.13.07/k5j - 42.0.11 version.** All other builds are rejected.
- This tool **installs the modifications only; it does not uninstall them**.
- To remove the client modifications, restore the original `Warframe.x64.exe` from the same game build and remove the `LotusGameRules.lua!75_*` file generated under `OpenWF\Content Replacements\0\Lotus\Scripts`.
- To remove the server modifications, run the `update script` inside SpaceNinjaServer to resynchronize its source code.
- The client portion supports only the versions and SHA-256 hashes explicitly listed by the tool. It will not force modifications onto an unknown EXE or unknown Lua file.
- The server portion is not pinned to a single Git commit, but it must pass structural compatibility checks.

## Requirements

- Windows PowerShell
- A complete OpenWF client installation, including `Warframe.x64.exe` and `Cache.Windows`.
- A complete SpaceNinjaServer source tree.
- Internet access may be required to download the pinned Warframe Exporter and any missing npm dependencies.

## How to use

Completely exit the Warframe client and SpaceNinjaServer:

```cmd
Install.cmd -ServerRoot "D:\Program Files\SpaceNinjaServer" -ClientRoot "D:\Program Files\WF\install\230411\8617432299175747361"
```
replaced "D:\Program Files\SpaceNinjaServer" and "D:\Program Files\WF\install\230411\8617432299175747361" with your own paths.

![Demo](demo.png)

After a successful installation, `START ARBITRATION4 SERVER.cmd` will be created in the server root directory. Use that script to start the server from then on. It starts only the already-built server; it does not run Git updates or overwrite the Arbitration4 server modifications.

**Do not use `UPDATE AND START SERVER.bat` unless you intend to remove the server modifications through an update.**

You can explicitly specify the installation directories by powershell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Arbitration4.ps1 `
  -ClientRoot "D:\Program Files\WF\install\230411\8617432299175747361" `
  -ServerRoot "D:\Program Files\WF\SpaceNinjaServer"
```

The installer follows a fail-fast policy. It writes changes only after every input file has passed its version, structure, and hash checks.

## Distribution Notice

This package does not include Warframe client files, modified executables, unpacked game Lua files, or the complete SpaceNinjaServer source code.

## License

This project is licensed under the MIT License. See [LICENSE.txt](LICENSE.txt).

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party software and services.