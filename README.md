# Paper Reader

macOS 原生论文阅读与 Markdown 笔记工作台。当前交付 **Phase 1 技术验证版，以及部分 Phase 2 基础联动能力**。这是能构建、启动、编辑、保存和导出的原生应用；完整的日常使用 MVP 仍需下一阶段完善。

## 构建与运行

需要 macOS、Xcode（支持 Swift 6）以及命令行工具。部署目标 macOS 14；本次实测为 Apple Silicon、macOS 27.3、Xcode 27、Swift 6.4。Intel 和旧版系统尚未验证。

```sh
./scripts/build-app.sh
open "build/Paper Reader.app"
```

工程已提交离线编辑器构建产物，因此只构建原生应用时不要求 Node 或联网。修改编辑器时需要 Node.js 20.19+（本次使用 26）：

```sh
cd WebEditor
npm ci
npm run build
cd ..
./scripts/build-app.sh
```

有 `node_modules` 时，打包脚本自动重建编辑器。完整测试中的 jsdom 需要 Node 20.19+。前端依赖全部锁定在 `package-lock.json`。

构建和临时签名放在 `~/Library/Caches/PaperReader/Build/`，避免同步目录给 `.app` 添加 Finder 属性而破坏签名。`build/Paper Reader.app` 是指向完整应用的启动软链接，**不是便携副本**。可迁移的应用包为 `build/PaperReader-macOS.zip`，解压后可将应用拖入 Applications。也可用 `PAPER_READER_BUILD_DIR` 自定义非同步构建目录。当前使用本地 ad-hoc 签名，未公证；不提供 App Store 发布包。

Xcode 可直接打开 `Package.swift` 阅读、调试工程。命令行推荐上述脚本；本机同步目录中的默认 `.build` 会受到 File Provider 的签名属性影响。

## 当前可用

- SwiftUI + AppKit 原生窗口、菜单、文件选择和设置；三栏可拖动、收起，记忆分栏宽度和面板显隐。
- 文献列表支持搜索、按标题/导入时间排序；PDF 文件选择导入与拖入入口。当前是平面文献库，尚非完整文件树。
- PDFKit 连续滚动、缩放、适合窗口、上一页/下一页、页码跳转、原文搜索、选区与复制。
- 最近三个 PDF 的内存缓存；每篇论文记忆页码和缩放设置。尚未恢复页内精确滚动位置。
- 真正的离线 Tiptap 所见即所得编辑器：标题、段落、粗斜体、删除线、`==高亮==`、引用、代码、列表、任务列表、Tab/Shift+Tab 缩进、表格、超链接和图片。
- KaTeX 行内/块级公式；点击公式打开 LaTeX 编辑面板，改写可撤销。
- 标准 `.md` 文件导入、编辑、保存和导出。导入会检查支持语法的语义往返；资源中的 PNG/JPEG/GIF/WebP 相对图片会复制并改写为独立资源路径。
- 原生保存面板直接导出笔记 PDF，使用 WebKit 的异步分页打印；无需 Typora、Pandoc 或在线服务。导出先写临时文件，再原子替换目标。
- PDF 框选以 3× 分辨率从 PDF 坐标渲染 PNG，插入笔记光标位置；图片和摘录保留论文 ID、页码、原文矩形及独立来源索引。
- 点击截图或其来源链接回到 PDF，并用独立临时高亮层标出区域。无需修改原 PDF，即使图表区域没有文字也能反馈位置。
- 每篇论文用 UUID 关联独立笔记；350 ms 自动保存、切换/导出/退出前同步编辑器并刷新保存队列。
- 笔记原子写入，保留 `note.previous.md`。保存时检测外部内容变更，保留 `note-conflict-*.md`，不会直接覆盖外部版本。
- 统一 CommandRegistry，设置中可配置应用命令的单字符组合键，并提示已知系统保留键和应用内冲突。原生文本编辑及窗口命令保留系统行为。

首次启动可在 File 菜单选择“打开示例论文”。示例 PDF 在本地生成，没有下载第三方论文。

## 快捷键

| 操作 | 默认快捷键 |
| --- | --- |
| 导入 PDF | Cmd+O |
| 保存笔记 | Cmd+S |
| PDF 框选截图 | Cmd+Option+S，拖动选择；Esc 取消 |
| 摘录 PDF 选中文字 | Cmd+Shift+E |
| 放大 / 缩小 | Cmd+= / Cmd+- |
| 适合窗口 | Cmd+0 |
| 文献库 / 笔记显隐 | Cmd+Option+1 / Cmd+Option+2 |
| 设置 | Cmd+, |
| 打印当前论文 | Cmd+P |
| 关闭窗口 | Cmd+W |

截图/摘录亦可从 PDF 右键菜单和工具栏调用。笔记工具栏支持格式命令；文本编辑区使用 Tiptap 的标准编辑快捷键。完整命令覆盖、按键录制器和更全面的系统级冲突检查留待 Phase 3。

## 文件与恢复

默认文献库：`~/Library/Application Support/PaperReader/Library/`。可设置 `PAPER_READER_LIBRARY=/absolute/path` 使用其他独立文献库。

```text
Library/
  library.sqlite                  SQLite 索引（WAL）
  <paper UUID>/
    paper.json                    稳定 ID、标题、阅读状态
    paper.pdf                     导入原件的副本
    note.md                       普通 UTF-8 Markdown
    note.previous.md              上一个完整笔记版本
    note-conflict-<UUID>.md        检测到外部修改时保留的编辑副本
    sources.json                  截图与摘录来源索引
    assets/
      <UUID>.png
```

PDF 不会被截图、摘录或来源高亮修改。导入后移动外部原件不影响文献关联。备份时退出应用并复制整个 Library；重新指定到复制后的目录即可。启动时扫描 `paper.json` 并重建 SQLite 索引，因此丢失索引仍可从普通文件恢复。请勿删除每篇论文的 `paper.json`；尚未实现无 manifest 的孤立文件恢复界面。

保存冲突发生后，当前笔记停止自动写回，自己的版本已经存入冲突副本。用“在 Finder 中显示文件”比较并合并，然后重新打开该论文以读取外部版本。当前是**保存时的冲突检测**，未提供实时文件监视或图形化合并器。恢复前一个版本可在退出应用后将 `note.previous.md` 复制回 `note.md`。

Markdown 导出生成 `<UUID>/note.md`、`assets/`、`sources.json` 和 `paper.json` 文件夹；不复制整篇 PDF。资源为相对路径。其他 Markdown 软件能读取文字、公式源码和图片；`paperreader://` 来源回跳需要本应用及对应文献索引。

## 测试

```sh
./scripts/test.sh
```

该脚本运行编辑器测试、依赖审计、Swift XCTest、原生构建，并在**真实应用窗口与 WKWebView** 中运行集成自测。需要图形化 macOS 登录会话；会短暂打开测试窗口。集成数据使用新建的 `/tmp/PaperReader-Integration.XXXXXX`，不使用默认文献库。测试产物保留在临时目录方便检查；每次结果写入 `build/integration-results.json`。集成测试会使用同一 bundle 的窗口恢复偏好，但不会修改用户论文文件。

已通过 **6 项 Swift 测试、9 项编辑器测试、24 项原生集成检查**。包含四种页面旋转、非零 crop box 原点、文件安全、真实 JS 桥接自动保存、独立笔记切换、公式重新编辑/撤销、Markdown 图片资源迁移、来源回跳，以及长笔记 11 页导出。已实际操作原生界面验证公式、拖动截图、快捷键冲突和保存面板导出；已渲染检查导出 PDF 首尾页。

具体证据、性能样本和未测试范围见 [验证记录](docs/VALIDATION.md)。架构与阶段任务见 [架构说明](docs/ARCHITECTURE.md)。

## 当前限制与下一步

**Phase 1 已完成的验证范围**：PDFKit/WKWebView 共存、可调整三栏、PDF 坐标截图、支持语法的 Markdown 往返、离线 KaTeX 编辑和渲染。已扩展部分基础联动，尚未宣称完整 Phase 2 MVP。

- Markdown 适配器仍属上游 beta。保证测试覆盖语法的语义一致，**不保证源文件空白、列表符号等逐字节不变**。YAML、原始 HTML 和脚注目前拒绝导入；不能安全往返的已有笔记显示为只读原文。任意 Markdown 方言仍需扩展兼容测试。
- 图片暂不支持拖动调尺寸、远程图片下载或引用上级目录资源。导入资源必须位于所选 `.md` 的目录内；来源 sidecar 的跨文献迁移尚未实现。
- 表格仅基础编辑，无完整行列管理面板；Mermaid 代码块可作为代码保存，尚未渲染图表。复杂 LaTeX、特别长的表格/代码行、超大图片仍需导出专项测试。
- 没有 PDF 目录面板、密码解锁、OCR、完整文件夹树、重命名/移动/删除、独立笔记窗口或完整恢复管理界面。
- 尚未实现 Phase 3：持久批注/绘制、激光笔、多栏感知聚焦、元数据查询、真实格式参考文献导出，以及大型论文性能优化。
- 尚未实现 Phase 4：AI Provider、Codex App Server、云 API、流式对话、联网检索与 AI 笔记差异预览。应用中没有假聊天或占位 AI 按钮。
- 当前未使用账户或云同步；未实现多进程同时编辑同一文献库的锁定。请只运行一个正式实例使用同一库。

下一阶段优先补齐文件树、阅读状态精确恢复、编辑器兼容性和导出边界测试，再推进批注、多栏聚焦与 AI。

## 依赖与许可证

| 依赖 | 固定版本 | 许可证 / 用途 |
| --- | --- | --- |
| Tiptap core、StarterKit 及使用的扩展 | 3.33.0 | MIT，编辑器与 ProseMirror 集成 |
| `@tiptap/markdown` | 3.33.0 | MIT，官方 Markdown 解析/序列化，beta |
| KaTeX | 0.18.10 | MIT，使用数学扩展声明支持且未弃用的版本 |
| esbuild | 0.28.2 | MIT，构建工具 |
| jsdom | 27.4.0 | MIT，仅测试 |
| PDFKit / WebKit / SQLite | 系统 SDK | Apple 系统框架 / 系统 SQLite，无额外下载 |

引入前检查了 npm 包许可证、最近维护信息、peerDependencies 和实际安装源码中的 API。本次 npm 审计无已知漏洞。第三方许可证随应用保存在 `Editor/THIRD-PARTY-NOTICES.txt`；源代码和离线产物均保留，可复现构建。运行编辑器不请求 CDN 或远程字体，资源请求由受限的本地 URL scheme 提供。

API 依据：[Tiptap Markdown](https://tiptap.dev/docs/editor/markdown/getting-started/installation)、[Tiptap Mathematics](https://tiptap.dev/docs/editor/extensions/nodes/mathematics)、[Apple PDFPage](https://developer.apple.com/documentation/pdfkit/pdfpage)、[Apple WebKit 打印](https://developer.apple.com/documentation/webkit/wkwebview/printoperation(with:))。异步打印行为另参考了 [WebKit 官方实现](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/mac/WKPrintingView.mm)。
