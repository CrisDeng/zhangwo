# 参与贡献

欢迎参与"掌握"项目的开发！🎉

## 快速链接

- **GitHub:** https://github.com/CrisDeng/zhangwo
- **使用教程:** https://docs.qq.com/doc/DSkFCZ3hVWVBuT2Jy

## 如何贡献

1. **Bug 修复** → 直接提交 PR
2. **新功能** → 先开 Issue 讨论
3. **文档改进** → 欢迎 PR

## 提交 PR 前

- 本地测试通过
- 运行 lint：`pnpm lint`
- 保持 PR 专注（一个 PR 只做一件事）
- 描述清楚改动内容和原因

## 开发环境

```bash
# 安装依赖
pnpm install

# 编译打包 (双架构)
BUILD_ARCHS=all ./scripts/package-mac-app.sh

# 创建 DMG
./scripts/create-dmg.sh ./dist/掌握.app
```

## 致谢

感谢所有贡献者！

本项目基于以下开源项目：
- [OpenClaw](https://github.com/openclaw/openclaw)
- [qqbot](https://github.com/sliverp/qqbot)
