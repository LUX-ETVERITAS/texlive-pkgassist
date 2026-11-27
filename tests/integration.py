"""Run against a writable, scheme-basic TeX Live installation (as in CI)."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

SCRIPT = Path(__file__).resolve().parents[1] / "texlive-pkgassist.lua"


def run(cwd, env, *args, success=True, script=SCRIPT):
    result = subprocess.run(
        ["texlua", str(script), *args], cwd=cwd, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        encoding="utf-8", errors="replace", timeout=900,
    )
    print(result.stdout, flush=True)
    assert (result.returncode == 0) == success, result.returncode
    return result.stdout


def main(work):
    env = dict(os.environ, TEXMFHOME=str(work / "user tree"))
    assert run(work, env, "--version").strip() == "texlive-pkgassist 0.1.1"
    paper = work / "my paper.tex"
    paper.write_text(r"\documentclass{article}\begin{document}Test.\end{document}")
    # Invoke the installed short command from a separate project directory.
    bindir = work / "package tools"
    bindir.mkdir()
    for name in ("tlpa", "tlpa.cmd", SCRIPT.name):
        shutil.copy2(SCRIPT.with_name(name), bindir / name)
    alias_env = dict(env, PATH=str(bindir) + os.pathsep + env["PATH"])
    alias = ["cmd.exe", "/d", "/c", "tlpa"] if os.name == "nt" else ["tlpa"]
    subprocess.run(alias + ["--tree", "user", paper.name], cwd=work, env=alias_env,
                   check=True, timeout=120)
    assert paper.with_suffix(".pdf").read_bytes().startswith(b"%PDF")
    invalid = subprocess.run(alias + ["--tree", "invalid"], cwd=work, env=alias_env)
    assert invalid.returncode == 2
    run(work, env, "--tree", "invalid", paper.name, success=False)
    log = run(work, env, "--tree=system", "--usermode", paper.name, success=False)
    assert "Conflicting installation tree options" in log
    fixture = Path(__file__).with_name("readonly.lua").resolve()
    windows = os.name == "nt"
    log = run(work, env, str(SCRIPT), "retry", paper.name, script=fixture, success=windows)
    assert "TEST read-only system tree" in log
    if windows:
        assert "TEST Windows elevation requested" in log
        log = run(work, env, str(SCRIPT), "cancel", paper.name, script=fixture, success=False)
        assert "TEST Windows elevation requested" in log and "System tree installation did not complete" in log
    else:
        assert "Ask an administrator to run tlmgr install booktabs" in log
    assert not (work / "user tree/tlpkg/texlive.tlpdb").exists()

    paper.write_text(r"""\documentclass{article}
% \usepackage{this-comment-is-not-a-dependency}
\usepackage
  {changepage,
   marginnote}
\begin{document}Text.\end{document}
""")
    log = run(work, env, "--tree=user", "--preflight", paper.name)
    assert log.count("texlive-pkgassist: tlmgr install") == 1
    assert "texlive-pkgassist: tlmgr install changepage marginnote" in log
    assert log.count("This is pdfTeX") == 1
    assert (work / "my paper.pdf").read_bytes().startswith(b"%PDF")
    assert (work / "user tree/tlpkg/texlive.tlpdb").is_file()
    assert "texlive-pkgassist: tlmgr install" not in run(work, env, paper.name)

    # Expansion hides the name from the lexical scanner.
    paper.write_text(r"""\documentclass{article}
\def\mypackage{needspace}\usepackage{\mypackage}
\begin{document}Text.\end{document}
""")
    log = run(work, env, "--usermode", "--preflight", paper.name)
    assert "texlive-pkgassist: tlmgr install needspace" in log

    paper.write_text(r"\documentclass{article}\begin{document}\unknownTestCommand\end{document}")
    log = run(work, env, paper.name, success=False)
    assert "Undefined control sequence" in log
    assert "texlive-pkgassist: tlmgr install" not in log

    log = run(work, env, "--usermode", "--require-tool",
              "autoinstall-unavailable-tool=example", paper.name, success=False)
    assert "Missing tool on PATH: autoinstall-unavailable-tool" in log
    assert "texlive-pkgassist: tlmgr install" not in log

    # A file:line diagnostic with a filename split by TeX's line wrapping.
    missing = "autoinstall-test-file-with-a-deliberately-long-name.sty"
    paper.write_text(r"\documentclass{article}\begin{document}\errmessage{LaTeX Error: File `"
                     + missing + r"' not found}\end{document}")
    log = run(work, dict(env, max_print_line="60"), paper.name, success=False)
    assert "No runtime package in the repository provides " + missing in log

    font = work / "font.tex"
    font.write_text(r"""\documentclass{article}
\usepackage{fontspec}
\setmainfont{Libertinus Serif}
\begin{document}Font test.\end{document}
""")
    run(work, env, "--usermode", "--engine", "lualatex", "--font",
        "Libertinus Serif=libertinus-fonts", font.name)
    assert (work / "font.pdf").read_bytes().startswith(b"%PDF")

    bib = work / "refs.bib"
    bib.write_text('@book{example, author={Doe, Jane}, title={CI Book}, year={2025}, publisher={P}}')
    paper = work / "bibliography.tex"
    paper.write_text(r"""\documentclass{article}
\usepackage[backend=biber]{biblatex}
\addbibresource{refs.bib}
\begin{document}\cite{example}\printbibliography\end{document}
""")
    run(work, env, "--tree", "system", "--preflight", paper.name)
    assert "CI Book" in (work / "bibliography.bbl").read_text(encoding="utf-8")
    assert "Please (re)run Biber" not in (work / "bibliography.log").read_text(errors="replace")
    assert (work / "bibliography.pdf").read_bytes().startswith(b"%PDF")


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="autoinstall ci ") as directory:
        main(Path(directory))
