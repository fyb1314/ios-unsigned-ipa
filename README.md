# 偶尔的PIA工具 · 未签名 IPA 制作工程

一个可编译成 **未签名 IPA** 的 iOS App 工程。产物不含任何证书和签名，拿到后由你自己用爱思助手（或同类工具）签名、安装到 iPhone。

- 语言：Swift 5 + SwiftUI
- 最低系统：iOS 15.0
- 架构：arm64（真机）
- 功能：只读展示设备名称 / 硬件型号 / 系统 / 屏幕分辨率 / 磁盘 / 内存 / 电池，支持一键复制报告
- 特性：不联网、不请求任何权限、无第三方依赖

---

## 一、Windows 用户（无 Mac）—— 推荐路径

整个构建跑在 GitHub 的 macOS 云主机上，你本地只需要浏览器。

### 1. 注册 GitHub 并建仓库

1. 打开 <https://github.com>，注册/登录。
2. 点右上角 **+** → **New repository**。
3. 名字随意，例如 `ipa-toolbox`。
4. **务必选 Public**（公开仓库的 Actions 免费额度无限；私有仓库每月只有 2000 分钟，也够用）。
5. 不要勾选 "Add a README"（我们本地已有文件），直接 **Create repository**。

### 2. 上传本目录所有文件

仓库创建页会显示上传入口。也可以装 [GitHub Desktop](https://desktop.github.com/)（图形化，不用记命令）。

需要上传的文件清单：

```
iOSApp/
├── .github/workflows/build-ipa.yml
├── IPATemplate/
│   ├── IPATemplateApp.swift
│   ├── ContentView.swift
│   ├── DeviceInfoModel.swift
│   ├── InfoRow.swift
│   └── Assets.xcassets/
│       ├── Contents.json
│       └── AppIcon.appiconset/
│           ├── Contents.json
│           ├── icon_1024.b64    # 图标（base64 文本，CI 里解码成 PNG）
│           └── icon_1024.png    # 本地构建产物，不用上传（已 gitignore）
├── project.yml
├── build_ipa_local.sh
├── make_icon.py                 # CI 图标缺失时的占位图标兜底
├── update_icon.py               # 换图标工具
└── README.md
```

> `.github` 是隐藏文件夹，上传时别漏掉 —— 漏了就没有自动构建。
> `icon_1024.png` 是本地构建产物（已被 .gitignore 排除），不用上传，CI 会从 `.b64` 解码。

### 3. 触发构建

两种方式任选：

- **自动**：文件推送到 `main` 分支即触发（workflow 已配 `push: branches: [main]`）
- **手动**：仓库页面 → **Actions** → 左侧选 **build-unsigned-ipa** → 右侧 **Run workflow** → 保持默认 `Release` → 再点绿色 **Run workflow**

等 3～8 分钟，出现绿色对勾即成功。构建结束后会自动建一个 issue 报告结果
（成功时附 IPA 大小和 SHA256，失败时附日志尾部）。

### 4. 下载 IPA

- 点进这次成功的运行记录
- 页面底部 **Artifacts** 区有 `IPATemplate-unsigned-ipa`
- 下载后解压，得到 `IPATemplate-unsigned.ipa`

### 5. 签名并安装

1. 打开爱思助手，连接 iPhone
2. 进 **工具箱 → IPA 签名**
3. 选 **自购证书**（用你自己的 p12 + mobileprovision）或 **个人证书**（Apple ID）
4. 添加 `IPATemplate-unsigned.ipa`，签名
5. 签名完成后在「已签名 IPA」里点安装，手机桌面即出现「偶尔的PIA工具」

---

## 一补、全自动 API 部署（github.com 不通时的通道）

有些网络环境下 `github.com` 的网页 / git / SSH 都不通，但 `api.github.com` 是通的。
本工程附带 `deploy_to_github.py`：**不走 git 协议、不需要 gh CLI**，纯 REST API 完成
「建仓库 → 上传全部文件（含二进制）→ 触发 Actions → 轮询构建 → 取回 IPA → 本地校验」全流程。

```bash
# 1. 到 GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
#    生成 token，勾选 repo + workflow 两个权限，有效期建议设为 7 天
set GITHUB_TOKEN=ghp_你的token

# 2. 一条命令搞定（默认创建公开仓库 ios-unsigned-ipa）
python deploy_to_github.py

# 可选参数
python deploy_to_github.py --repo 我的仓库名 --private   # 指定仓库名 / 建私有库
python deploy_to_github.py --dry-run                     # 只本地预演，不上传
```

脚本自动处理的事：

- 仓库名被占用 → 自动加时间戳后缀重试
- 二进制文件（PNG 图标）base64 上传，逐字节校验一致性
- 新建仓库后 Actions 注册 workflow 有延迟 → 自动重试触发
- 构建失败 → 自动拉取日志尾部，方便定位
- **IPA 取回双通道**：先试 Actions artifact（下载跳转常被网络卡住），失败自动改从 `dist` 分支 raw 内容接口取
- 取回后本地校验 IPA 结构（`Payload/` 在根 / 无签名残留 / arm64 Mach-O / Bundle ID）

> **安全提醒**：classic token 的 `repo` 权限能操作你所有仓库，用完请立刻到
> GitHub → Settings → Developer settings 里吊销。
> workflow 末尾的「Push IPA to dist branch」步骤是给上面这条兜底通道用的，不想要可以删掉该步骤，不影响主流程。

---

## 二、有 Mac 的用户

```bash
cd iOSApp
brew install xcodegen
./build_ipa_local.sh Release
```

产物为同目录下的 `IPATemplate-unsigned.ipa`。

---

## 三、改自己的东西

### 改 App 名称 / Bundle ID

编辑 `project.yml`：

```yaml
CFBundleDisplayName: 偶尔的PIA工具      # 桌面显示名
PRODUCT_BUNDLE_IDENTIFIER: dev.ipa.toolbox   # 包名，改成你的
CFBundleShortVersionString: "1.0.0"     # 版本号
CFBundleVersion: "1"                    # 构建号
```

### 改图标

图标在仓库里以 **base64 文本** `IPATemplate/Assets.xcassets/AppIcon.appiconset/icon_1024.b64`
存放（云端推送通道只可靠传文本，CI 构建时自动解码回 PNG）。换图标一条命令：

```bash
pip install pillow
python update_icon.py 你的图片.jpg        # 自动裁剪正方形、缩放到 1024、去 Alpha
```

要求：**1024×1024、正方形、不透明、无圆角**（系统自动裁圆角）、**不带 Alpha 通道**。
`update_icon.py` 会自动处理这些。也可以随时用 `python make_icon.py` 重新生成占位图标。

### 改界面

| 文件 | 作用 |
|---|---|
| `ContentView.swift` | 页面布局、导航栏按钮 |
| `DeviceInfoModel.swift` | 采集哪些信息、文案格式 |
| `InfoRow.swift` | 单行「标签 + 值」样式 |

---

## 四、构建产物说明

workflow 里做了这些事保证「真的没签名」：

```bash
rm -rf  Payload/IPATemplate.app/_CodeSignature
rm -f   Payload/IPATemplate.app/embedded.mobileprovision
chmod 755 Payload/IPATemplate.app/IPATemplate
zip -qry IPATemplate-unsigned.ipa Payload
```

并带一道自检，任一项不通过就直接让构建失败：

| 检查项 | 要求 |
|---|---|
| `Payload/IPATemplate.app/Info.plist` | 必须存在 |
| `Payload/IPATemplate.app/IPATemplate` | 可执行文件必须存在 |
| `_CodeSignature` | **必须不存在** |
| Mach-O magic | 必须是 `cf fa ed fe`（arm64 小端） |

---

## 五、常见问题

**Q：Actions 里报 `xcodegen: command not found`**
A：workflow 已自动 `brew install xcodegen`。若失败，在仓库 **Settings → Actions → General** 确认 Actions 已启用。

**Q：报 `No profiles for 'dev.ipa.toolbox' were found`**
A：说明签名没关干净。确认 `project.yml` 里有 `CODE_SIGNING_ALLOWED: "NO"`，且 workflow 传了 `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`。

**Q：下载的 IPA 爱思签名时报「IPA包格式错误」**
A：IPA 必须是 `Payload/` 在根目录的标准 ZIP。本工程产出已保证，不要用 Windows 资源管理器"发送到压缩文件夹"再打包，会带上多余目录层。

**Q：装到手机上报「无法验证 App」**
A：未签名 IPA 本来就不能直接装。必须先用爱思签名；个人证书模式签出来的 App 有效期 7 天，过期重签即可。

**Q：公开仓库会不会泄露代码？**
A：会。这是你的 App 源码，本就该公开或私有自定。若不想公开，私有仓库也能用，只是有免费分钟数限制。

---

## 六、目录结构

```
iOSApp/
├── .github/
│   └── workflows/
│       └── build-ipa.yml        # 自动构建未签名 IPA
├── IPATemplate/
│   ├── IPATemplateApp.swift     # @main 入口
│   ├── ContentView.swift        # 主界面
│   ├── DeviceInfoModel.swift    # 设备信息采集
│   ├── InfoRow.swift            # 列表行组件
│   └── Assets.xcassets/         # 图标资源
│       └── AppIcon.appiconset/
│           ├── Contents.json
│           ├── icon_1024.b64    # 图标的 base64 文本版（CI 解码用）
│           └── icon_1024.png    # 解码产物，本地构建用
├── project.yml                  # XcodeGen 工程描述
├── build_ipa_local.sh           # Mac 本地构建
├── make_icon.py                 # 占位图标生成器
├── update_icon.py               # 换图标工具（任意图 → 1024 无 Alpha）
├── deploy_to_github.py          # 纯 API 自动部署脚本（不上传到仓库）
└── README.md
```
