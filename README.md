# DSAE

Dynamic Semantic Autoencoder — 纯本地 iOS 文本/文件加密器。

## 技术

- 口令派生：PBKDF2-HMAC-SHA256，120,000 次迭代，16 字节随机盐
- 加密：AES-256-GCM（CryptoKit，带认证）
- 文件格式：`DSAE1` + salt(16) + nonce + 密文 + tag
- 文本格式：`DSAE1-` + Base64
- 无网络代码、无第三方依赖、不收集任何数据

## 构建（GitHub Actions）

推送 `main` 或手动触发 `Build unsigned IPA`，产物为未签名 `DSAE.ipa`。

本地构建：

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project DSAE.xcodeproj -scheme DSAE -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```
