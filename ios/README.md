# 随手存 iOS 云构建版

要求 iOS 17 或以上。此包是源码，不是已经编译成功的 IPA。本机为 Windows，没有 Xcode，首次编译与模拟器测试由 GitHub Actions 执行。

## GitHub 操作

1. 解压 SuishouCun-iOS-GitHub.zip。根目录应有 ios、.github、README.md。
2. 登录 GitHub，右上角 + > New repository，仓库名 suishou-ios，选 Private，勾选 Add a README，点击 Create repository。
3. 在仓库 Code 页，选择 Add file > Upload files。拖入解压后的 ios 文件夹，点击 Commit changes。
4. .github 是隐藏目录，浏览器拖拽可能漏传。用 Add file > Create new file，新文件名填写 .github/workflows/build-ios.yml。把工程包里 ios/github-workflows/build-ios.yml 的全文粘贴到编辑框，再 Commit changes。
5. 打开 Actions。若出现启用提示，允许当前仓库运行工作流。选择 Build iOS > Run workflow > main > Run workflow。
6. 等待运行变为绿色。进入本次运行，找到 Artifacts，下载 SuishouCun-unsigned-IPA。下载的是 ZIP，解压后才是 SuishouCun-unsigned.ipa。
7. 若红色失败，下载 build-log 或展开失败步骤，将错误日志发回。不必反复改签名参数。
8. 把 IPA 传到手机，在全能签里使用你已有的有效证书及描述文件签名并安装。编译阶段不需要向 GitHub 上传签名证书。

## 手机首次使用

设置中接口默认是 https://game.wxshares.com/ssc/index.php，填写此前注册的随手存用户名和密码，点击登录并同步。不要填写数据库用户名和数据库密码。

已登录时凭证存入 iOS 钥匙串，再次打开使用已有凭证。Token 到期需重新登录。文本缓存位于 App 自己的 Documents/notes.json，保存前保留 notes.json.backup。卸载 App 会删除沙盒数据，所以升级请保持相同 Bundle ID 和签名身份，避免先卸载。

列表支持搜索、点正文复制、新增、编辑、上移、下移、置顶。打开 App、回到前台、下拉刷新、修改后会尝试同步。断网时本地改动保留，下次同步重试。发生云端较新版本冲突会显示错误并保留本地修改，不会静默报告成功。

## 当前范围与限制

- 采用现有 PHP 接口，不需要再次执行 SQL，不需要重新上传服务器文件。
- GitHub 编译和模拟器测试尚未运行；产物需在你的 iPhone 上签名安装后验证。
- 现有云端接口不支持可靠的跨设备删除标记，iOS 暂不开放删除。
- Windows 1.2.2 的排序上传仍需另行修复；iOS 已上传 sort_order 和更新时间，但旧 Windows 合并逻辑不会可靠应用云端排序。不要把这版称为完整双端排序正式版。
- iOS 无法提供跨其他 App 的常驻悬浮圈；复制后自行切换到目标 App 粘贴。
- 仍使用当前服务器的更新时间比较协议；同时离线编辑同条记录可能需要人工处理冲突。
- 默认未配置自定义桌面 App 图标，不影响编译；系统可能显示默认图标。

工程由 XcodeGen 根据 ios/project.yml 生成。GitHub 工作流会编译 iPhone arm64、运行 JSON 日期/字段兼容性测试，并将真机 .app 放进 Payload 目录打成未签名 IPA。
