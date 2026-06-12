# 贡献指南

感谢你考虑为校园网认证系统贡献代码！

## 🤔 如何贡献

### 报告Bug

如果你发现了Bug，请通过[Issues](https://github.com/pengcong226/campus-auth-openwrt/issues)提交：

1. 使用清晰的标题描述问题
2. 提供详细的环境信息：
   - OpenWrt版本
   - 路由器型号
   - 相关日志（使用代码块）
3. 描述复现步骤
4. 说明预期行为和实际行为

### 建议新功能

欢迎提出新功能建议：

1. 在Issues中创建新issue
2. 使用 `[Feature]` 标签
3. 详细描述功能需求和使用场景
4. 如果可能，提供实现思路

### 提交代码

#### 开发环境准备

```bash
# 1. Fork本项目到你的GitHub账号

# 2. Clone你的fork
git clone https://github.com/pengcong226/campus-auth-openwrt.git
cd campus-auth-openwrt

# 3. 创建功能分支
git checkout -b feature/your-feature-name

# 或者创建修复分支
git checkout -b fix/your-bug-fix
```

#### 代码规范

**Shell脚本**

- 使用 `#!/bin/sh` 而非 `#!/bin/bash`（兼容性更好）
- 遵循 [ShellCheck](https://www.shellcheck.net/) 规范
- 使用4空格缩进
- 函数和变量使用snake_case命名
- 添加有意义的注释

```sh
# 好的示例
get_wan_ip() {
    ip -4 addr show "$WAN_DEV" 2>/dev/null | \
        grep "inet " | \
        awk '{print $2}' | \
        cut -d'/' -f1 | \
        head -1
}

# 避免
getWanIp(){
    ip -4 addr show $WAN_DEV 2>/dev/null|grep "inet "|awk '{print $2}'|cut -d'/' -f1|head -1
}
```

**Lua代码（LuCI）**

- 使用2空格缩进
- 函数使用snake_case命名
- 添加必要的安全检查

```lua
-- 好的示例
function safe_filter(str)
    if not str then return "" end
    return str:gsub("[^%w%s%-%_%.]", "")
end

-- 避免
function safeFilter(str)
    return str:gsub("[^%w%s%-%_%.]", "")
end
```

**HTML/CSS/JavaScript**

- 使用语义化HTML标签
- CSS类名使用kebab-case
- JS使用现代ES6+语法

#### 提交规范

使用清晰的提交信息：

```bash
# 功能添加
git commit -m "Add: 支持Telegram通知"

# Bug修复
git commit -m "Fix: 修复密码加密时的特殊字符处理"

# 文档更新
git commit -m "Docs: 更新配置说明文档"

# 性能优化
git commit -m "Optimize: 减少认证请求的内存占用"

# 重构
git commit -m "Refactor: 重构认证逻辑提高可读性"
```

#### 测试

提交前请确保：

1. **脚本语法检查**
   ```bash
   # Shell脚本
   shellcheck install.sh

   # Lua语法
   luac -p /usr/lib/lua/luci/controller/campus_auth.lua
   ```

2. **路由器实测**
   - 在真实OpenWrt环境测试
   - 测试各项功能是否正常
   - 检查日志输出

3. **兼容性测试**
   - OpenWrt 19.07+
   - 不同路由器型号
   - 不同网络环境

4. **边界情况**
   - 无网络连接时的处理
   - 认证失败的恢复
   - 并发请求的处理

#### 提交Pull Request

1. **确保代码质量**
   ```bash
   # 检查代码风格
   shellcheck install.sh

   # 本地测试
   ./install.sh
   ```

2. **推送到你的fork**
   ```bash
   git push origin feature/your-feature-name
   ```

3. **创建Pull Request**
   - 访问原项目页面
   - 点击 "New Pull Request"
   - 选择你的分支
   - 填写PR模板：

   ```markdown
   ## 变更类型
   - [ ] Bug修复
   - [ ] 新功能
   - [ ] 文档更新
   - [ ] 代码重构
   - [ ] 性能优化

   ## 变更说明
   详细描述你的变更内容...

   ## 测试情况
   - 测试环境：OpenWrt 21.02 on Xiaomi Router AX6
   - 测试结果：通过所有测试

   ## 相关Issue
   Fixes #123

   ## 检查清单
   - [ ] 代码符合项目规范
   - [ ] 已添加必要注释
   - [ ] 已更新相关文档
   - [ ] 已充分测试
   ```

4. **等待审核**
   - 维护者会审核你的代码
   - 根据反馈进行必要的修改
   - 审核通过后会被合并

## 🎯 开发路线

优先级较高的功能：

### 高优先级
- [ ] 支持更多学校认证系统
- [ ] 企业微信通知
- [ ] Telegram通知
- [ ] 认证成功率统计

### 中优先级
- [ ] Web界面添加统计图表
- [ ] 支持多账号轮换
- [ ] 自动检测认证参数
- [ ] OpenAppFilter集成

### 低优先级
- [ ] 自动更新功能
- [ ] 配置导入导出
- [ ] 多语言支持

## 📚 技术文档

### 架构说明

```
┌─────────────────────────────────────────┐
│           Web界面 (LuCI)                 │
│  ┌───────────┬───────────┬───────────┐ │
│  │ 状态监控  │ 配置管理  │ 日志查看  │ │
│  └───────────┴───────────┴───────────┘ │
└─────────────────────────────────────────┘
                   ↕
┌─────────────────────────────────────────┐
│          核心认证脚本                     │
│  ┌───────────────────────────────────┐  │
│  │ 认证逻辑  状态检测  钉钉通知       │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
                   ↕
┌─────────────────────────────────────────┐
│          系统集成层                      │
│  ┌─────────┬──────────┬──────────────┐ │
│  │ mwan3   │ crontab  │ UCI配置      │ │
│  └─────────┴──────────┴──────────────┘ │
└─────────────────────────────────────────┘
```

### 数据流

```
用户请求
    ↓
LuCI界面
    ↓
API处理 (controller)
    ↓
UCI配置读取
    ↓
认证脚本执行
    ↓
网络请求 (curl)
    ↓
认证服务器
    ↓
结果验证 (ping)
    ↓
钉钉通知
    ↓
日志记录
```

### 关键函数

**认证流程**
- `check_need_auth()` - 检测认证状态
- `do_auth()` - 执行认证
- `send_dingtalk()` - 发送通知

**辅助函数**
- `get_wan_ip()` - 获取WAN IP
- `get_wan_mac()` - 获取WAN MAC
- `log()` - 日志记录

**钩子函数**
- `mwan3_hook()` - mwan3事件钩子
- `handle_schedule()` - 定时任务处理

## 🔍 调试技巧

### 查看详细日志

```bash
# 实时日志
tail -f /var/log/campus_auth.log

# 手动运行带调试
bash -x /root/campus_auth.sh login
```

### 测试认证请求

```bash
# 测试HTTP状态
curl -I --interface wan http://connect.rom.miui.com/generate_204

# 抓取认证包
tcpdump -i wan -A port 443
```

### 模拟事件

```bash
# 模拟mwan3事件
INTERFACE='wan' ACTION='ifup' /etc/mwan3.user

# 模拟定时期段
/root/campus_auth.sh midnight
/root/campus_auth.sh morning
```

## 💡 开发建议

1. **保持兼容性** - 确保在OpenWrt 19.07+上正常运行
2. **错误处理** - 所有关键操作都要有错误处理
3. **日志记录** - 重要操作都要记录日志
4. **资源优化** - 注意路由器资源限制（CPU/内存）
5. **安全性** - 敏感信息加密存储，防止注入攻击
6. **用户友好** - 提供清晰的错误提示和文档

## 📋 代码审查清单

提交前请检查：

- [ ] 代码符合项目编码规范
- [ ] 添加了必要的注释和文档
- [ ] 处理了所有可能的错误情况
- [ ] 没有引入安全漏洞
- [ ] 在实际环境中测试通过
- [ ] 提交信息清晰明确
- [ ] 更新了相关文档（如需要）

## 🙋 获取帮助

- 📖 阅读 [Wiki](https://github.com/pengcong226/campus-auth-openwrt/wiki)
- 💬 在 [Discussions](https://github.com/pengcong226/campus-auth-openwrt/discussions) 提问
- 🐛 提交 [Issue](https://github.com/pengcong226/campus-auth-openwrt/issues)

## 📜 许可证

提交代码即表示你同意将代码以MIT许可证开源。

---

再次感谢你的贡献！🎉
