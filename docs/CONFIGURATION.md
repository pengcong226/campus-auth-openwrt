# 配置说明

## 目录

- [基础配置](#基础配置)
- [高级配置](#高级配置)
- [多线路配置](#多线路配置)
- [通知配置](#通知配置)
- [自定义适配](#自定义适配)

## 基础配置

### 必需参数

```bash
# 学号
uci set campus_auth.@auth[0].username='你的学号'

# 密码（明文）
uci set campus_auth.@auth[0].password='你的密码'

# 或加密存储（推荐）
/root/campus_auth.sh encrypt '你的密码'

# 保存配置
uci commit campus_auth
```

### 可选参数

```bash
# 认证域名
uci set campus_auth.@auth[0].auth_domain='auth.gxstnu.edu.cn'

# 认证服务器IP（绕过DNS解析）
uci set campus_auth.@auth[0].server_ip='172.20.4.3'

# AC网关IP
uci set campus_auth.@auth[0].wlanacip='172.16.1.82'

# AC名称
uci set campus_auth.@auth[0].wlanacname='GXSTNU-BRAS'

# WAN接口名称
uci set campus_auth.@auth[0].wan_device='wan'

# WAN网关
uci set campus_auth.@auth[0].wan_gateway='172.17.21.1'
```

## 高级配置

### 重试机制

```bash
# 最大重试次数（默认3次）
uci set campus_auth.@auth[0].max_retry='5'

# 重试间隔（默认5秒）
uci set campus_auth.@auth[0].retry_delay='10'

# 外网拨号结果轮询次数（默认20次）
uci set campus_auth.@auth[0].auth_poll_max='20'

# 外网拨号结果轮询间隔（默认2秒）
uci set campus_auth.@auth[0].auth_poll_interval='2'

uci commit campus_auth
```

### 认证参数

```bash
# VLAN ID（默认0）
uci set campus_auth.@auth[0].vlan='0'

# 认证类型（默认0）
uci set campus_auth.@auth[0].auth_type='0'

# 是否绑定MAC（默认0）
uci set campus_auth.@auth[0].isBindMac='0'

# 页面ID（默认5）
uci set campus_auth.@auth[0].pageid='5'

# 模板类型（默认1）
uci set campus_auth.@auth[0].templatetype='1'

uci commit campus_auth
```

### 定时任务

系统自动配置了以下定时任务：

```
0 0 * * *   # 每天0点断网
0 6 * * *   # 每天6点恢复
*/30 * * * * # 每30分钟检查认证状态
```

手动修改定时任务：

```bash
# 编辑crontab
crontab -e

# 添加自定义任务
0 7 * * * /root/campus_auth.sh login >/dev/null 2>&1
```

## 多线路配置

### mwan3基础配置

```bash
# 查看mwan3状态
mwan3 status

# 查看接口状态
mwan3 interfaces

# 查看策略
mwan3 policies

# 查看规则
mwan3 rules
```

### 自定义线路优先级

编辑 `/etc/config/mwan3`：

```
config member 'wan_m1'
    option interface 'wan'
    option metric '1'      # 优先级最高
    option weight '10'

config member 'lan1_m1'
    option interface 'lan1'
    option metric '2'      # 次优先级
    option weight '10'

config member 'u20_m1'
    option interface 'u20'
    option metric '3'      # 最后选择
    option weight '10'
```

### 故障检测参数

```bash
# WAN接口检测配置（通过UCI）
uci set mwan3.wan.track_method='ping'
uci set mwan3.wan.track_ip='223.5.5.5 119.29.29.29'
uci set mwan3.wan.interval='3'      # 检测间隔
uci set mwan3.wan.timeout='2'       # 超时时间
uci set mwan3.wan.down='3'          # 失败3次判定为离线
uci set mwan3.wan.up='3'            # 成功3次判定为在线

uci commit mwan3
/etc/init.d/mwan3 restart
```

## 通知配置

### 钉钉机器人

#### 创建钉钉机器人

1. 打开钉钉群设置 → 群机器人 → 添加机器人
2. 选择"自定义"机器人
3. 设置机器人名称和头像
4. 安全设置选择"加签"，记录密钥（SEC开头）
5. 记录Webhook地址

#### 配置通知

```bash
# 启用通知
uci set campus_auth.@notify[0].enabled='1'

# 设置Webhook
uci set campus_auth.@notify[0].webhook='https://oapi.dingtalk.com/robot/send?access_token=xxxxx'

# 设置加签密钥
uci set campus_auth.@notify[0].secret='SECxxxxxxxx'

# 选择通知事件
uci set campus_auth.@notify[0].notify_success='1'  # 认证成功
uci set campus_auth.@notify[0].notify_fail='1'     # 认证失败
uci set campus_auth.@notify[0].notify_schedule='1' # 定时切换

uci commit campus_auth
```

#### 测试通知

```bash
# 手动触发认证（会发送通知）
/root/campus_auth.sh login
```

### 企业微信（计划中）

暂不支持，欢迎贡献代码。

### Telegram（计划中）

暂不支持，欢迎贡献代码。

## 自定义适配

### 适配其他学校

#### 步骤1: 抓包分析

1. 浏览器打开开发者工具（F12）→ Network标签
2. 访问认证页面，输入账号密码登录
3. 找到POST请求（通常是 `webauth.do` 或类似）
4. 记录以下信息：
   - 请求URL和域名
   - POST参数名称和格式
   - Cookie处理方式

#### 步骤2: 修改配置参数

编辑安装脚本中的默认值：

```bash
# 第17-22行
AUTH_DOMAIN_DEFAULT="auth.your-school.edu.cn"
AUTH_SERVER_IP_DEFAULT="x.x.x.x"
WLANACIP_DEFAULT="x.x.x.x"
WLANACNAME_DEFAULT="YOUR-SCHOOL-BRAS"
WAN_GATEWAY_DEFAULT="x.x.x.x"
```

#### 步骤3: 修改认证请求

编辑 `/root/campus_auth.sh` 中构造认证数据的片段：

```bash
# 根据实际抓包结果调整参数
local data="wlanacip=${AC_IP}&wlanacname=${AC_NAME}&wlanuserip=${ip}&mac=${macl}"
data="${data}&scheme=https&serverIp=tomcat_server1:443&hostIp=http://127.0.0.1:8446/"
data="${data}&pageid=${PAGEID}&templatetype=${TEMPLATETYPE}&portalVer=0&tservertypeid=axe"
data="${data}&userId=${USERNAME}&passwd=${PASSWORD}"
# 添加其他必需参数...
```

#### 步骤4: 测试验证

```bash
# 测试配置
/root/campus_auth.sh test

# 手动认证测试
/root/campus_auth.sh login

# 查看日志
tail -f /var/log/campus_auth.log
```

### 自定义认证逻辑

如果认证流程差异较大，可以修改 `do_auth()` 函数（第252-349行）：

```bash
do_auth() {
    # 1. 自定义获取Cookie的方式
    curl -sk --interface "$WAN_DEV" "https://your-auth-url" ...

    # 2. 自定义认证请求
    curl -sk --interface "$WAN_DEV" -d "your-data" ...

    # 3. 自定义验证方式
    if your_verification_command; then
        log "INFO" "认证成功"
        return 0
    fi
}
```

### 添加新的通知方式

编辑 `/root/campus_auth.sh` 中的 `send_dingtalk()` 函数，添加新的通知函数：

```bash
send_telegram() {
    local title="$1"
    local content="$2"
    local bot_token=$(uci -q get campus_auth.@notify[0].telegram_bot_token)
    local chat_id=$(uci -q get campus_auth.@notify[0].telegram_chat_id)

    [ -z "$bot_token" ] || [ -z "$chat_id" ] && return 0

    curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
        -d "chat_id=${chat_id}" \
        -d "text=${title}%0A%0A${content}" \
        >/dev/null 2>&1 &
}
```

然后在 `do_auth()` 成功/失败处调用：

```bash
send_dingtalk "标题" "内容"
send_telegram "标题" "内容"
```

## 配置备份与恢复

### 备份配置

```bash
# 备份配置文件
cp /etc/config/campus_auth /etc/config/campus_auth.backup

# 或导出为文本
uci export campus_auth > campus_auth_backup.txt
```

### 恢复配置

```bash
# 恢复配置文件
cp /etc/config/campus_auth.backup /etc/config/campus_auth

# 或从文本导入
uci import campus_auth < campus_auth_backup.txt
```

### 重置为默认配置

```bash
# 删除配置
uci delete campus_auth
uci commit campus_auth

# 重新运行安装脚本
/tmp/campus_auth_install.sh
```

## 环境变量

可以在脚本开头设置环境变量：

```bash
export LOG_FILE="/var/log/campus_auth.log"
export COOKIE_FILE="/tmp/campus_auth_cookie"
export LOCK_FILE="/tmp/campus_auth.lock"
```

## 性能优化

### 减少检测频率

```bash
# 将检测间隔从30分钟改为1小时
sed -i 's|*/30 \* \* \* \*|0 \* \* \* \*|' /etc/crontabs/root
/etc/init.d/cron restart
```

### 调整mwan3检测

```bash
# 增加检测间隔，降低CPU使用
uci set mwan3.wan.interval='5'
uci set mwan3.lan1.interval='10'
uci commit mwan3
/etc/init.d/mwan3 restart
```

### 日志轮转优化

日志自动保留最新300行，可在脚本第196行修改：

```bash
# 修改为保留最新500行
tail -n 500 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
```
