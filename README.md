# PodHours 本地版（iOS App 壳）

一个极简的原生壳 App：全屏 WKWebView 显示内置的 PodHours 离线页面
（与网页版同一份已验证代码，零联网、零统计）。

- 选择 iPhone「健康」导出的 export.zip / export.xml，在本机解析，
  按耳机统计累计聆听时长、日均、使用次数、最长一次、平均音量、≥80dB 占比等。
- GitHub Actions（macOS）云端编译，产出**未签名** IPA 并发布到本仓库 Release `v1`。
- 安装：下载 IPA 后用自己的 Apple ID 自签（全能签 / Sideloadly / iLoader 等），
  免费 ID 签名有效期 7 天，到期重签即可。

工程由 XcodeGen（project.yml）生成，图标由 tools/make_icon.py 在 CI 里生成。
