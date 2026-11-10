# Paper Reader

macOS 原生论文阅读与 Markdown 笔记工作台，SwiftUI / AppKit / PDFKit / 离线 Tiptap。当前为 **0.3.0 开发预览版：Phase 1 技术验证及 Phase 2–4 的核心实现**，可构建、运行、编辑、保存和导出。高级功能的边界和未验收范围列在文末。

官网：[www.weitao-jiang.cn/paper-reader/](https://www.weitao-jiang.cn/paper-reader/) · [下载与版本记录](https://github.com/CBDT-JWT/paper-reader/releases)

0.3.0 新增 Sparkle 在线更新接口、应用菜单“检查更新”和自动检查设置、拖拽安装 DMG、双语官网及可重复的发布流程。**正式 Developer ID 签名和 Apple 公证仍需开发者账号配置；预览包不进入正式更新源。** 发布操作和凭证边界见 [发布文档](docs/RELEASING.md)，本轮实际测试与跳过项见 [0.3.0 验证记录](docs/RELEASE_VALIDATION.md)。

## 本轮交互修复

- 阅读工具栏直接显示带文字的 **“聚焦 / Focus”** 按钮；窄栏也保留直接入口，二级菜单只保留聚焦参数。
- 暗场改为不激活的 NSPanel 系统覆盖层，监听原生全屏和 Space 切换。新增进入全屏、在全屏内开启、退出全屏后的实际窗口验证，检查遮罩确实属于活动 Space。
- 文件树提供直接的新建文件夹按钮，以及“文件名 / 标题 / 导入时间”和倒序选择；默认按文件名自然排序，数字 2 排在 10 前，重启保留设置。新导入记录保留原始文件名，旧记录兼容标题回退。
- 文件树改用原生 NSOutlineView，避免按钮点击与拖动冲突，阅读位置变化保持拖拽源稳定。文件夹使用当前窗口的命名表单，可新建、展开、重命名、嵌套和移动；拖动论文及文件夹使用专门的数据类型，移除文件夹时内容上移。组织操作读取最新记录保存，避免旧阅读状态覆盖移动结果。选择文件夹后导入 PDF 会放入该文件夹。
- IEEE/矢量图页面按实际字符坐标重建文字行，过滤微小不可见 LaTeX 元数据，用正文的典型宽度/位置识别栏，避免居中标题和密集图标签连接两栏；相邻标题与正文按真实文字框和最近行中心定位。

- 已加入应用图标，包含 Dock/Finder 所需的 16–1024 像素 ICNS 表示；源图与生成提示词保存在 [assets](assets/README.md)，构建时自动打包。

本轮验证细节与未覆盖范围见 [修复验证记录](docs/WORKSPACE_FIXES.md)。

## 构建和运行

需要 macOS 14+、Xcode（Swift 6）及 Python 3。首次构建需联网解析并下载锁定的 Sparkle 2.10.1（MIT），后续正常使用不依赖 CDN。本次实测 Apple Silicon、macOS 27.3、Xcode 27、Swift 6.4；Intel 和旧系统尚未实测。

```sh
./scripts/build-app.sh
open "build/Paper Reader.app"
```

已提交离线编辑器产物，原生构建无需 Node 或在线 CDN。修改前端及运行完整测试需要 **Node 22.12+**（Mermaid 的要求；本机使用 26.4）：

```sh
cd WebEditor
npm ci
npm run build
cd ..
./scripts/test.sh
```

打包脚本在存在 `WebEditor/node_modules` 时自动重建前端。依赖版本锁定于 `package-lock.json`。

构建与 ad-hoc 签名位于 `~/Library/Caches/PaperReader/Build/`，避免同步目录的 Finder 属性破坏签名。`build/Paper Reader.app` 为启动软链接；便携包为 **`build/PaperReader-macOS.zip`**，解压后可拖入 Applications。使用 `PAPER_READER_BUILD_DIR` 可指定其他非同步构建目录。开发构建为 ad-hoc 签名，尚未完成 Developer ID 签名/公证，也未上架 App Store。`scripts/build-dmg.sh` 可制作带背景的 Applications 拖拽安装包。Xcode 可打开 `Package.swift` 调试。

## 已实现

| 阶段 | 当前能力 |
| --- | --- |
| Phase 1 | 真实 PDFKit 与 WKWebView 共存、可调三栏、PDF 坐标截图、Markdown 往返校验、离线 KaTeX 源码编辑与渲染 |
| Phase 2 | 文件夹树、搜索排序、拖入 PDF、重命名、移动、可恢复删除；UUID 关联笔记；截图和摘录来源回跳；自动保存；Markdown 与资源打包、原生笔记 PDF 导出；菜单、工具栏、右键命令 |
| Phase 3 | 独立批注侧文件，高亮、直线、矩形、自由绘制、临时激光笔、撤销重做、带批注 PDF 导出；多栏聚焦与整屏暗场；快捷键录制与冲突提示；Crossref / arXiv 元数据和四种参考文献格式；阅读位置恢复及最近三个 PDF 缓存 |
| Phase 4 | Codex App Server、OpenAI 兼容云 API、本地 HTTP 推理服务接口；模型列表；流式多轮问答、停止、会话恢复；选区文字/图像与论文页上下文；来源页链接；外部学术检索；笔记差异确认、版本检查与撤销 |

界面、菜单、设置、编辑器弹窗与辅助功能标签统一跟随系统语言，提供简体中文和英文，其他语言回退英文。更改系统或单应用语言后重新启动生效；论文正文、用户笔记和文献标题保持原文。工具栏根据宽度收纳操作，图标菜单不再将下拉箭头挤在图标旁。

编辑器支持标题、粗斜体、删除线、`==高亮==`、列表/任务/缩进、引用、代码、表格、链接、相对图片与拖动调整显示尺寸、行内/块级公式。点击公式可重新编辑 LaTeX；Mermaid 使用离线库以严格安全模式渲染，保留可编辑源码。导出笔记 PDF 使用 WebKit 原生异步分页，等待公式、图片、图表就绪，不依赖外部排版程序。

首次体验可在“文件 / File”菜单打开示例论文。示例 PDF 本地生成，不下载第三方论文。

## 阅读聚焦

从阅读工具栏的“聚焦”按钮或“阅读”菜单开启，默认快捷键 **Cmd+Option+F**。暗场覆盖所有连接屏幕的完整区域，包括文献树、笔记、菜单栏和 Dock；仅当前 PDF 的目标文字区域透亮。遮罩只绘制半透明黑色，不读取或录制屏幕内容，也不拦截鼠标。

- 鼠标移动跟随文字行；**单击固定，↑ / ↓ 前后移动，再次单击恢复跟随**。拖动选字不触发固定。
- 阅读顺序在同一排版带中先左栏到底，再右栏到顶；跨栏标题、公式等单独处理，邻行高亮不会同时照亮相邻栏。
- 可设置上下行数、强度和手动栏数/当前栏。识别为启发式分析，异常排版可手动选择。
- 滚动后不会因原高亮离开视口而关闭整个暗场；鼠标模式重新定位可见区域。锁定模式保留原行。
- 扫描件没有 OCR 时使用区域聚焦，可手动限定栏。按 **Esc** 退出；切换到其他应用自动隐藏遮罩。

## AI 配置与权限

在设置的 AI 页选择 Provider：

1. **Codex App Server**：使用已安装并登录的 Codex，可修改可执行文件路径；点击“读取模型”后选择。实际验证 CLI 0.167.0。本机 Codex 进程不表示本地模型推理。
2. **云端 API**：填写 OpenAI 兼容基础地址、模型和 API Key；密钥仅保存于 macOS Keychain。要求 HTTPS。
3. **本地 HTTP 模型**：连接已经运行的兼容服务，如 `http://127.0.0.1:11434/v1`；应用不附带模型权重或推理引擎。仅回环 HTTP 被允许。

Cmd+Option+G 呼出阅读区底部输入框，Enter 发送、Shift+Enter 换行、Esc 关闭。可展开会话窗口。发送时包含当前论文和笔记的有界上下文，有选区时携带文字与 PDF 渲染图；视觉理解需要支持图像的模型。使用云端或 Codex 时这些上下文会发往所选模型服务，发送前请自行选择合适的 Provider。

模型只获得明确的研究工具：`readPaper`、`getSelection`、`getPageContext`、`searchPaper`、`readNote`、`proposeNoteEdit`、`insertNoteBlock`、`searchWeb`、`getBibliography`。没有任意路径读写、Shell、外部插件或系统操作工具。Codex 启动时关闭这些能力，未知请求和权限提升请求被拒绝。

AI 提议修改后，笔记保持原样；用户查看前后差异并明确应用，才进入编辑器历史。笔记已被改动时拒绝过期提议。外部检索为 **Crossref 学术出版物元数据检索**，会返回真实 DOI/URL，尚非通用网页浏览器。回答页链接可回到论文；模型的推导和公式识别仍需与原文核对。

## 常用快捷键

| 操作 | 默认键 |
| --- | --- |
| 导入 / 保存笔记 | Cmd+O / Cmd+S |
| 截图 / 摘录 | Cmd+Option+S / Cmd+Shift+E |
| 阅读聚焦 / 选中文字高亮 | Cmd+Option+F / Cmd+Shift+H |
| 询问 AI | Cmd+Option+G |
| 缩放 / 适合窗口 | Cmd+=、Cmd+- / Cmd+0 |
| 文献库 / 笔记显隐 | Cmd+Option+1 / Cmd+Option+2 |
| 打印 / 设置 | Cmd+P / Cmd+, |

应用命令由统一 CommandRegistry 管理，设置中点击录制框，再“应用”。Delete 清除、Esc 取消；提示系统保留键与应用内冲突。Tiptap 常规文字编辑键和系统文本/窗口命令保留原行为，尚未提供逐项重映射。

## 文件、备份与恢复

默认库：`~/Library/Application Support/PaperReader/Library/`；可用 `PAPER_READER_LIBRARY=/absolute/path` 指定隔离库。

```text
Library/
  library.sqlite                 可重建 SQLite 索引，WAL
  folders.json                   文件夹组织结构
  .Trash/<paper UUID>/           可恢复的整篇文献目录
  <paper UUID>/
    paper.json                   UUID、逻辑文件名、元数据、文件夹、阅读位置
    paper.pdf                    导入原件的副本
    note.md                      标准 UTF-8 Markdown
    note.previous.md             上一个完整版本
    note-conflict-<UUID>.md       冲突时保留自己的版本
    sources.json                 摘录/截图来源页和 PDF 坐标
    annotations.json             独立批注
    conversation.json            本地对话历史
    assets/<UUID>.png
```

截图、笔记、批注和 AI 编辑不修改原始 PDF。带批注 PDF 导出为新文件，PDFKit 注释图在独立辅助进程的主线程构建和序列化，避免阻塞阅读界面。移动外部原件不影响导入副本；重命名/整理文件夹不改变论文 UUID。

350 ms 自动保存，切换/退出/导出前同步编辑器。保存使用原子替换和版本校验；每两秒检查当前笔记的外部变更，无本地待保存内容时重新载入，有冲突则保留副本并停止自动覆盖。尚无图形合并器：在 Finder 比较冲突文件、合并后重新打开论文。退出后可用 `note.previous.md` 恢复上一版本。

备份应退出应用后复制整个 Library。丢失 SQLite 索引可由 `paper.json` 重建；不要删掉 manifest。文献树菜单可恢复应用回收站中的论文。笔记导出生成含 `.md`、相对资源和来源索引的目录，不复制论文 PDF。`paperreader://` 来源链接需要本应用和对应文献索引。

## 验证与限制

运行 `./scripts/test.sh`，在隔离临时库中执行 19 项 Swift 测试、11 项编辑器测试，以及中英文各 60 项真实原生/WKWebView 集成检查；并运行依赖审计。`PAPER_READER_LIVE_TESTS=1 ./scripts/test.sh` 额外连接真实 Crossref 与已登录 Codex，发送的仅为合成测试文档。详见 [验证记录](docs/VALIDATION.md) 和 [架构](docs/ARCHITECTURE.md)。

本版的明确边界：

- Markdown 保证已支持语法的语义往返，不保证空白和列表符号逐字节一致。上游官方 Markdown 适配器仍为 beta。YAML、原始 HTML、脚注拒绝导入；不可安全转换的笔记以只读原文保护。
- 不下载远程图片；导入资源限制在所选 Markdown 目录内。图片显示尺寸存于标准图片 title 中，其他编辑器可能忽略尺寸。来源侧文件跨文献迁移尚未实现。
- 独立笔记窗口为只读查看；表格是基础编辑。超长表格、极宽代码、复杂公式和所有 Mermaid 类型尚未全面验收。
- 不含 OCR、加密 PDF 解锁、通用网页检索或 OpenAlex 适配器。扫描件只做区域聚焦。多栏识别不保证任意复杂版式都准确。
- 云 API 已用真实本地 HTTP/SSE 服务验证协议，尚未使用用户云密钥做实际供应商验收；真实 Codex 的文字生成、模型列表和图像理解已验证。
- 尚未覆盖百页扫描件、海量文献库、Intel/旧系统、多显示器热插拔的人工验收、断电/磁盘耗尽及多个进程同时编辑同一库。请只用一个正式实例打开同一库。
- 未公证、未上架；没有把单次示例打开速度当成所有论文首屏一秒内的承诺。

## 依赖与许可证

| 依赖 | 版本 | 许可证 |
| --- | --- | --- |
| Tiptap 及使用的扩展、官方 Markdown 适配器 | 3.33.0 | MIT |
| KaTeX | 0.18.10 | MIT |
| Mermaid | 12.3.0 | MIT |
| esbuild / jsdom（开发测试） | 0.28.2 / 27.4.0 | MIT |
| PDFKit / WebKit / SQLite | 系统提供 | Apple SDK / SQLite 公有领域 |

依赖引入前检查了许可证、维护信息、实际源码 API 与运行时要求；当前 npm 审计无已知漏洞。许可证随包保存在 `Editor/THIRD-PARTY-NOTICES.txt`，编辑器 JS、CSS、公式字体、图表渲染库全部离线打包。

API 依据：[Tiptap Markdown](https://tiptap.dev/docs/editor/markdown/getting-started/installation)、[Tiptap Mathematics](https://tiptap.dev/docs/editor/extensions/nodes/mathematics)、[Mermaid](https://mermaid.js.org/config/usage)、[Apple PDFPage](https://developer.apple.com/documentation/pdfkit/pdfpage)、[WebKit 原生打印](https://developer.apple.com/documentation/webkit/wkwebview/printoperation(with:))、[Codex App Server](https://learn.chatgpt.com/docs/app-server)、[Crossref](https://www.crossref.org/documentation/retrieve-metadata/rest-api/)、[arXiv API](https://info.arxiv.org/help/api/index.html)。
