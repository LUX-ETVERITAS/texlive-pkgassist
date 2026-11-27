# texlive-pkgassist

版本 0.1.0 · 维护者 Ruilin Mao · [MIT 许可证](LICENSE)

用 TeX Live 自带的 `texlua` 编译 LaTeX 文档。脚本按文件名在仓库中查找所属宏包，例如缺少 `subcaption.sty` 时安装 `caption`。支持 Windows、Linux 上的上游 TeX Live 和 macOS 上的 MacTeX。

## 编译

在项目目录中运行，确保 `texlua`、所选引擎和 `tlmgr` 来自同一套安装。默认引擎为 `pdflatex`，也支持 `xelatex`、`lualatex` 和 `latex`。

```sh
texlua texlive-pkgassist.lua main.tex
texlua texlive-pkgassist.lua --engine xelatex --preflight "中文论文.tex"
```

`--preflight` 扫描主文件导言区里的 `\documentclass`、`\usepackage` 和 `\RequirePackage`。脚本跳过已能找到的文件，将其余名字合并为一次仓库查询，批量安装唯一匹配的包，再启动引擎。静态扫描不会展开宏或判断条件分支，因而可能预装未使用的包。子文件、动态加载和传递依赖仍可在实际编译报错时补装。

脚本识别传统的 `!` 报错、带文件名和行号的诊断，以及跨行的文件名。候选包不唯一、找不到文件或出现普通编译错误时，会输出诊断并返回非零退出码。输出文件位于当前目录。Windows 文档路径支持空格，目前不支持百分号、感叹号和双引号。

## 选择安装树

| 选项 | 新宏包的安装位置 | 目标目录只读时 |
|---|---|---|
| `--tree system` | 当前 TeX Live 的系统树 | Windows 收到 `tlmgr` 的系统树只读诊断后请求 UAC 授权，Linux 和 macOS 输出所需的管理员安装命令并退出 |
| `--tree user` | 当前用户的 `TEXMFHOME` | 首次使用时按需初始化个人树，支持可重定位的宏包 |
| `--tree auto`（默认） | 先使用系统树 | 收到上述只读诊断后，尝试在个人树安装宏包；二进制工具仍需可写的系统树 |

```sh
texlua texlive-pkgassist.lua --tree system --preflight main.tex
texlua texlive-pkgassist.lua --tree user --preflight main.tex
```

`--usermode` 是 `--tree user` 的兼容写法。选项控制新增包的安装位置；引擎会继续使用正常搜索路径中已有的宏包。

在 Windows 上，只有显式选择系统树且普通权限安装遇到上述权限错误时，脚本才通过 PowerShell 的 `Start-Process -Verb RunAs` 为本次 `tlmgr install` 请求授权。是否需要确认或输入管理员凭据由 Windows 的 UAC 策略决定。取消或安装失败会终止本次构建。授权成功后，原进程继续以启动时的权限编译。预查找到的多个包可在同一次授权中安装，之后才发现的依赖可能再次触发授权。[Windows 授权机制](https://learn.microsoft.com/en-us/windows/win32/shell/launch)

服务器和 CI 如需动态安装二进制工具，请使用运行账户拥有的上游 TeX Live，或在镜像中预装工具。下载需要与本地 TeX Live 年份匹配的仓库。脚本通过 `tlmgr` 管理包；由 Debian/Ubuntu 的 APT 管理的系统树仍应通过发行版安装依赖。脚本不执行系统级更新。

## 参考文献、外部工具和字体

```sh
texlua texlive-pkgassist.lua --latexmk --preflight main.tex
texlua texlive-pkgassist.lua --require-tool makeindex=makeindex --latexmk main.tex
texlua texlive-pkgassist.lua --engine lualatex --font "Libertinus Serif=libertinus-fonts" main.tex
```

`--latexmk` 将构建交给 latexmk，它会跟踪输入变化，运行 Biber 等工具并完成后续编译。默认单轮引擎模式遇到 biblatex 请求运行 Biber 时也会转入 latexmk。缺少 latexmk 或 Biber 时，脚本会尝试安装对应的 TeX Live 包。运行工具还需要其平台依赖，例如 latexmk 所需的 Perl 模块。

对其他外部命令，可用 `--require-tool 命令=包名` 检查 PATH 并按需安装 TeX Live 包，由项目构建规则决定调用时机。对于 fontspec 报告的字体族，可用 `--font` 指定提供该字体的 TeX Live 包。两个选项都可重复。系统专有字体、TeX Live 仓库以外的工具需要由构建环境提供。

## GitHub 自动验证

项目的 GitHub Actions 工作流 在 push、pull request 和手动触发时分别使用 Ubuntu、Windows 和 macOS runner。每个任务从 `scheme-basic` 开始，运行同一份 [集成测试](tests/integration.py)，检查真实安装、PDF、错误退出和 Biber 生成的参考文献。

可以在本地一次性、可写的 `scheme-basic` 上运行 `python tests/integration.py`。测试会向这套 TeX Live 安装参考文献工具，批量安装测试另外使用临时个人树。初始系统树中应缺少 changepage、marginnote 和 needspace，以便验证实际补装过程。
