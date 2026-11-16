# 论文导入与 AI 收集

## 文件与链接

顶栏“导入论文”菜单提供本地 PDF 和“从链接导入论文…”两个入口，文件菜单也可调用。在文件树选中文件夹后开始导入，或使用该文件夹右键菜单，副本将放到对应文件夹。

链接输入支持 arXiv abs / pdf / html 地址、IEEE document / stamp / PDF 地址、DOI 链接和 PDF 直链。输入后按 Enter 或“下载并导入”，应用解析链接、下载至临时目录、验证 PDF，并复制到目标文件夹。目标文件夹在开始导入时确定，同名文件通过数字后缀区分。取消操作会停止当前请求并清理临时文件。

显式导入生成独立副本，源文件位于工作区内时也采用同一复制流程。“打开文件夹”按原结构扫描和索引。PDF 先复制到隐藏暂存文件，再发布至最终文件名，索引随后持久化。

## IEEE 和版本信息

IEEE 链接会读取论文页面 / PDF 网关并提取其 PDF 地址，使用请求所在网络的可用访问权限。公开副本回退通过同 DOI 的 OpenAlex 记录，下载来源和版本随文献记录保存。“文献信息”显示原论文链接、实际下载来源以及出版版本 / 作者接受稿 / 预印本标记。

本应用的下载会话独立于默认浏览器。来源未返回可访问 PDF 时，导入窗口提供来源网页入口，可使用浏览器下载文件后进行本地导入。只有通过 PDF 校验的文件才进入文献库。

## AI 工具

在 AI 连接设置中开启“允许外部学术检索”，可要求 AI 检索、收集并下载论文。

- `searchWeb(query, source?)` 使用 Crossref 或 arXiv，默认 Crossref，返回实际出版物元数据和来源 URL。
- `downloadPaper(url, folder?, fileName?)` 解析论文链接并导入副本。目标默认采用发送问题时选中的文件夹，folder 为相对工作区路径，空字符串表示根目录。工具返回文献 ID、保存路径、跳转链接、实际下载地址和版本。
- `downloadFile` 继续处理数据集等补充文件，已识别的论文链接采用论文导入流程。

AI 下载期间保持当前阅读上下文，结果中的 paperreader 链接可打开已入库论文。AI 笔记编辑继续使用差异确认。网络请求可取消，文件夹和文件名受工作区路径约束。

## 协议与依赖依据

实现复用 Foundation URLSession、XMLParser、NSFileCoordinator 和现有 PDF 校验。arXiv 元数据及 PDF 请求复用应用内的串行节流。IEEE 的页面、引用格式和 PDF 网关参数依据 Zotero 维护的 IEEE Xplore 翻译器核对。

- [arXiv 官方 API 手册](https://info.arxiv.org/help/api/user-manual.html)
- [Zotero IEEE Xplore 翻译器](https://github.com/zotero/translators/blob/master/IEEE%20Xplore.js)
- [OpenAlex 公开副本与版本说明](https://help.openalex.org/data/locations/)

## 本轮验证范围

遵照用户要求，跳过功能、界面和联网下载测试。执行 Swift 编译、离线编辑器构建、本地化、打包与分发检查。真实 arXiv / IEEE 下载、机构访问、公开副本回退、复制与取消操作及 AI 工具往返仍待运行验证。
