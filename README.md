# 校园网认证系统 - OpenWrt

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-Supported-brightgreen.svg)](https://openwrt.org/)
[![Platform](https://img.shields.io/badge/Platform-Router-orange.svg)]()

一个功能完整的校园网Portal认证系统，专为OpenWrt路由器设计，支持自动认证、多线路故障切换和Web管理界面。

## ✨ 主要特性

- 🔐 **自动认证** - Portal认证自动登录，支持重试机制
- 🔄 **多线路切换** - 通过mwan3实现WAN/LAN1/U20三线路故障转移
- ⏰ **定时管理** - 0点自动断网，6点自动恢复并认证
- 🌐 **Web管理界面** - LuCI界面提供状态监控、配置管理、日志查看
- 📱 **钉钉通知** - 认证状态变化时自动推送消息
- 🔒 **密码加密** - Base64 + 混淆加密存储密码
- 📊 **日志管理** - 自动日志轮转，保留最新记录

## 📋 系统要求

- OpenWrt 19.07+
- 路由器可用空间 > 500KB
- 依赖软件包：`curl`, `openssl-util`, `ip-full`, `mwan3`

## 🚀 快速开始

### 方法1: 一键安装

```bash
# 下载并执行安装脚本
curl -fsSL https://raw.githubusercontent.com/pengcong226/campus-auth-openwrt/main/install.sh | sh
```

### 方法2: 手动安装

```bash
# 1. 克隆仓库
git clone https://github.com/pengcong226/campus-auth-openwrt.git
cd campus-auth-openwrt

# 2. 上传到路由器
scp install.sh root@192.168.1.1:/tmp/campus_auth_install.sh

# 3. SSH到路由器执行安装
ssh root@192.168.1.1
chmod +x /tmp/campus_auth_install.sh
/tmp/campus_auth_install.sh
```

### 安装后配置

```bash
# 1. 设置账号密码
uci set campus_auth.@auth[0].username='你的学号'
uci set campus_auth.@auth[0].password='你的密码'

# 2. 加密密码（推荐）
/root/campus_auth.sh encrypt '你的密码'

# 3. 保存配置
uci commit campus_auth

# 4. 立即认证
/root/campus_auth.sh login
```

## 📖 使用指南

### Web界面

安装完成后，访问路由器LuCI界面：

```
http://192.168.1.1/cgi-bin/luci/admin/services/campus_auth
```

提供以下功能：
- **状态监控** - 实时查看认证状态、外网连接、接口信息
- **认证配置** - 配置账号、密码、服务器参数
- **通知设置** - 配置钉钉机器人通知
- **运行日志** - 查看认证日志，支持过滤和统计

### 命令行操作

```bash
# 立即认证
/root/campus_auth.sh login

# 检查认证状态
/root/campus_auth.sh check

# 显示详细状态
/root/campus_auth.sh status

# 加密保存密码
/root/campus_auth.sh encrypt '你的密码'

# 模拟0点断网
/root/campus_auth.sh midnight

# 模拟6点恢复
/root/campus_auth.sh morning

# 测试配置
/root/campus_auth.sh test
```

### 定时任务

系统自动配置了以下定时任务：
- **0:00** - 断开校园网，切换备用线路
- **6:00** - 恢复校园网并自动认证
- **每30分钟** - 检查认证状态，必要时重新认证

## ⚙️ 配置说明

### 认证参数配置

```bash
# UCI配置路径
/etc/config/campus_auth

# 主要配置项
config auth
    option username '学号'              # 认证账号
    option password 'ENC:xxxxxx'        # 加密密码
    option password_encrypted '1'       # 密码已加密
    option auth_domain 'auth.gxstnu.edu.cn'  # 认证域名
    option server_ip '172.20.4.3'       # 认证服务器IP
    option wlanacip '172.16.1.82'       # AC网关IP
    option wan_device 'wan'             # WAN接口名称
    option max_retry '3'                # 最大重试次数
    option retry_delay '5'              # 重试间隔(秒)
    option auth_poll_max '20'           # 外网拨号结果轮询次数
    option auth_poll_interval '2'       # 外网拨号轮询间隔(秒)
```

### 钉钉通知配置

```bash
# 启用钉钉通知
uci set campus_auth.@notify[0].enabled='1'
uci set campus_auth.@notify[0].webhook='https://oapi.dingtalk.com/robot/send?access_token=xxx'
uci set campus_auth.@notify[0].secret='SECxxxxxxxx'
uci commit campus_auth
```

### mwan3多线路配置

支持三条线路优先级：
1. **wan** - 校园网（优先级最高）
2. **lan1** - CPE备用网络
3. **u20** - 随身WiFi（最后手段）

当校园网认证失败或断开时，自动切换到备用线路。

## 🔧 工作原理

### 认证流程

```
1. 检测认证状态 → HTTP 204测试
2. 需要认证 → 访问BRAS重定向页并获取Cookie
3. 构造认证数据 → 发送到认证服务器
4. 如返回“正在进行外网拨号” → 轮询 getAuthResult.do
5. 验证结果 → HTTP 204 / Ping外网IP
6. 失败重试 → 最多重试3次
7. 钉钉通知 → 推送结果
```

### mwan3联动

```
mwan3事件 → WAN连接 → 触发认证钩子
         → WAN断开 → 切换备用线路
         → 故障检测 → 自动重连认证
```

## 📁 文件结构

```
/etc/config/campus_auth              # 配置文件
/usr/lib/campus_auth_crypto.sh       # 密码加密工具
/root/campus_auth.sh                 # 核心认证脚本
/etc/mwan3.user                      # mwan3事件钩子
/etc/config/mwan3                    # mwan3配置
/usr/lib/lua/luci/controller/campus_auth.lua      # LuCI控制器
/usr/lib/lua/luci/model/cbi/campus_auth/          # LuCI配置模型
/usr/lib/lua/luci/view/campus_auth/               # LuCI视图模板
/var/log/campus_auth.log             # 运行日志
```

## 🐛 故障排除

### 认证失败

```bash
# 1. 检查配置
/root/campus_auth.sh test

# 2. 查看日志
tail -f /var/log/campus_auth.log

# 3. 手动测试
curl -I --interface wan http://connect.rom.miui.com/generate_204
```

### Web界面无法访问

```bash
# 清除LuCI缓存
rm -rf /tmp/luci-*
/etc/init.d/uhttpd restart
/etc/init.d/rpcd restart

# 清除浏览器缓存（Ctrl+F5）
```

### mwan3未正常工作

```bash
# 检查mwan3状态
mwan3 status

# 重启mwan3
/etc/init.d/mwan3 restart

# 检查接口状态
ip route show table all
```

## 🤝 适配其他学校

修改以下参数即可适配其他学校：

```bash
# 认证域名
AUTH_DOMAIN_DEFAULT="auth.your-school.edu.cn"

# 认证服务器IP
AUTH_SERVER_IP_DEFAULT="x.x.x.x"

# AC网关IP
WLANACIP_DEFAULT="x.x.x.x"

# AC名称
WLANACNAME_DEFAULT="YOUR-SCHOOL-BRAS"

# WAN网关
WAN_GATEWAY_DEFAULT="x.x.x.x"
```

根据实际抓包调整认证POST参数（`campus_auth.sh` 第299-303行）。

## 📝 开发计划

- [ ] 支持更多通知方式（企业微信、Telegram）
- [ ] 添加认证成功率的统计图表
- [ ] 支持多账号轮换
- [ ] 自动检测并更新认证参数
- [ ] 添加OpenAppFilter集成

## 📄 许可证

本项目采用 [MIT 许可证](LICENSE)

## 🙏 致谢

- [OpenWrt](https://openwrt.org/) - 嵌入式设备Linux发行版
- [LuCI](https://github.com/openwrt/luci) - OpenWrt Web管理界面
- [mwan3](https://github.com/openwrt/packages/tree/master/net/mwan3) - 多WAN负载均衡

## 📮 反馈与贡献

欢迎提交 Issue 和 Pull Request！

- 🐛 Bug反馈：[Issues](https://github.com/pengcong226/campus-auth-openwrt/issues)
- 💡 功能建议：[Discussions](https://github.com/pengcong226/campus-auth-openwrt/discussions)
- 🔧 贡献代码：[Pull Requests](https://github.com/pengcong226/campus-auth-openwrt/pulls)

---

⭐ 如果这个项目对你有帮助，请给个Star支持一下！
