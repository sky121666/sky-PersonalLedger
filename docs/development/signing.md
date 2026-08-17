# 开发签名教程

本教程只说明如何为本地 Android/iOS 开发构建准备签名材料。Docker/Web 发布和本项目的 v1.0.8 截图不依赖这些材料。

## Android 开发 keystore

生成一个仅用于本机开发的 keystore：

    cd mobile/android
    keytool -genkeypair -v \
      -keystore app/upload-keystore.jks \
      -storetype JKS \
      -keyalg RSA \
      -keysize 2048 \
      -validity 10000 \
      -alias upload

创建 key.properties：

    storeFile=app/upload-keystore.jks
    storePassword=<本地密码>
    keyAlias=upload
    keyPassword=<本地密码>

然后构建：

    cd ..
    flutter build apk --debug
    flutter build apk --release

开发 keystore、key.properties 和生成的 APK 不应提交到 Git。正式商店发布需要独立的长期密钥、CI Secret 和变更记录，不要复用开发 keystore。

## iOS Simulator

iOS Simulator 不需要 Apple Developer 签名：

    cd mobile
    flutter build ios --simulator --debug
    flutter run -d C417531C-3ABC-4357-880C-4ECC9A1752D1

## iOS 真机/IPA

真机和 IPA 分发需要：

- Apple Developer Team；
- Distribution/Development certificate；
- Provisioning Profile；
- ExportOptions.plist；
- CI 中的证书密码和临时 keychain 密码。

这些材料只放在本地钥匙串或 GitHub Actions Secrets，不要写进仓库、README、Issue、日志或截图。

## 为什么正式分发需要签名

签名用于证明安装包来源、阻止包被篡改，并允许系统把新版本识别为同一个应用。它不是账本密码，也不是 API Key；仅在 Android/iOS 安装包构建和分发时使用。

