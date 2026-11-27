# texlive-pkgassist

Version 0.1.0 · Maintained by Ruilin Mao · MIT License

Compile a LaTeX document and install the TeX Live packages that supply its missing files. For example, when LaTeX reports a missing `subcaption.sty`, the script asks `tlmgr` which package provides it, installs `caption`, and retries the build.

## Quick start

Unpack the release and run the following from your document's project directory. Substitute the path to the unpacked script.

```sh
texlua /path/to/texlive-pkgassist.lua --tree user --preflight main.tex
```

Use `texlua`, `tlmgr`, and your LaTeX engine from the same upstream TeX Live installation on Windows or Linux, or from MacTeX on macOS. Package downloads use the configured TeX Live repository. It must match the year of the local installation.

- `--tree user` installs relocatable packages under `TEXMFHOME`. The script initializes the user tree as needed.
- `--tree system` installs into the selected TeX Live installation. On Windows, a recognized read-only installation error triggers a UAC request for the package installation. Compilation continues with the original process privileges.
- `--tree auto` (default) tries the system tree first and can retry a package installation in the user tree.
- `--preflight` checks explicit declarations in the main preamble and batches missing packages before starting the engine.
- `--latexmk` delegates multiple passes and bibliography processing to latexmk.

See the [user manual](texlive-pkgassist.pdf) for engine choices, external tools, font mappings and troubleshooting. Chinese instructions are available in [README-zh.md](README-zh.md).

Copyright (c) 2026 Ruilin Mao. The script, tests and documentation are distributed under the [MIT License](LICENSE).
