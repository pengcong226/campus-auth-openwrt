#!/bin/sh
# ============================================================
# 校园网认证系统 - 完整安装脚本 (安全增强版)
# 适用: OpenWrt 路由器
# 功能: 多线路故障切换 + 自动认证 + Web管理界面
# ============================================================

set -e

echo "=========================================="
echo "  校园网认证系统安装"
echo "=========================================="

# ============================================================
# 配置变量（可根据实际情况修改）
# ============================================================
AUTH_DOMAIN_DEFAULT="auth.gxstnu.edu.cn"
AUTH_SERVER_IP_DEFAULT="172.20.4.3"
WLANACIP_DEFAULT="172.16.1.82"
WLANACNAME_DEFAULT="GXSTNU-BRAS"
WAN_GATEWAY_DEFAULT="172.17.21.1"
WAN_DEVICE_DEFAULT="wan"

# 重试配置
MAX_RETRY_DEFAULT="3"
RETRY_DELAY_DEFAULT="5"

# ============================================================
# 1. 安装依赖
# ============================================================
echo "📦 检查并安装依赖..."
opkg update 2>/dev/null || true
for pkg in curl openssl-util ip-full; do
    opkg list-installed | grep -q "^$pkg -" || opkg install $pkg 2>/dev/null || true
done

# ============================================================
# 2. 创建配置文件
# ============================================================
echo "📝 创建配置文件..."
mkdir -p /etc/config

cat > /etc/config/campus_auth << 'EOF'
config auth
    option username ''
    option password ''
    option password_encrypted '0'
    option wlanacip '172.16.1.82'
    option wlanacname 'GXSTNU-BRAS'
    option server_ip '172.20.4.3'
    option auth_domain 'auth.gxstnu.edu.cn'
    option wan_device 'wan'
    option wan_gateway '172.17.21.1'
    option max_retry '3'
    option retry_delay '5'
    option auth_poll_max '20'
    option auth_poll_interval '2'
    option vlan '0'
    option auth_type '0'
    option isBindMac '0'
    option pageid '5'
    option templatetype '1'

config notify
    option enabled '0'
    option webhook ''
    option secret ''
    option notify_success '1'
    option notify_fail '1'
    option notify_schedule '1'

config mwan3_wan
    option track_method 'ping'
    list track_ip '223.5.5.5'
    list track_ip '119.29.29.29'
    option interval '3'
    option timeout '2'
    option down '3'
    option up '3'

config mwan3_lan1
    option track_method 'ping'
    list track_ip '119.29.29.29'
    list track_ip '223.5.5.5'
    option interval '5'
    option timeout '2'
    option down '3'
    option up '3'

config mwan3_u20
    option track_method 'ping'
    list track_ip '119.29.29.29'
    list track_ip '223.5.5.5'
    option interval '10'
    option timeout '3'
    option down '3'
    option up '3'
EOF

# ============================================================
# 3. 密码加密工具函数
# ============================================================
echo "🔐 安装密码加密支持..."

cat > /usr/lib/campus_auth_crypto.sh << 'CRYPTOEOF'
#!/bin/sh
# 简单的Base64加密（路由器环境适用）

encrypt_password() {
    local pwd="$1"
    if [ -z "$pwd" ]; then
        echo "用法: $0 encrypt <密码>" >&2
        return 1
    fi
    # Base64编码 + 简单混淆
    local enc=$(echo -n "$pwd" | base64 | tr 'a-zA-Z' 'n-za-mN-ZA-M')
    echo "ENC:$enc"
}

decrypt_password() {
    local enc="$1"
    if [ -z "$enc" ] || [ "${enc:0:4}" != "ENC:" ]; then
        # 未加密的明文密码，直接返回
        echo "$enc"
        return 0
    fi
    # 解混淆 + Base64解码
    local data="${enc:4}"
    echo "$data" | tr 'n-za-mN-ZA-M' 'a-zA-Z' | base64 -d 2>/dev/null
}

case "$1" in
    encrypt) encrypt_password "$2" ;;
    decrypt) decrypt_password "$2" ;;
    *) echo "用法: $0 {encrypt|decrypt} <value>" ;;
esac
CRYPTOEOF
chmod +x /usr/lib/campus_auth_crypto.sh

# ============================================================
# 4. 安装核心认证脚本
# ============================================================
echo "📝 安装核心认证脚本..."

cat > /root/campus_auth.sh << 'AUTHEOF'
#!/bin/sh
# ============================================================
# 校园网认证脚本 (安全增强版)
# ============================================================

LOG_FILE="/var/log/campus_auth.log"
COOKIE_FILE="/tmp/campus_auth_cookie"
LOCK_FILE="/tmp/campus_auth.lock"
SCRIPT_DIR="/usr/lib"

# 加载配置
load_config() {
    USERNAME=$(uci -q get campus_auth.@auth[0].username || echo "")
    PASSWORD=$(uci -q get campus_auth.@auth[0].password || echo "")
    PASSWORD_ENCRYPTED=$(uci -q get campus_auth.@auth[0].password_encrypted || echo "0")
    
    # 解密密码
    if [ "$PASSWORD_ENCRYPTED" = "1" ] && [ -n "$PASSWORD" ]; then
        PASSWORD=$($SCRIPT_DIR/campus_auth_crypto.sh decrypt "$PASSWORD" 2>/dev/null || echo "$PASSWORD")
    fi
    
    AC_IP=$(uci -q get campus_auth.@auth[0].wlanacip || echo "172.16.1.82")
    AC_NAME=$(uci -q get campus_auth.@auth[0].wlanacname || echo "GXSTNU-BRAS")
    AUTH_SERVER_IP=$(uci -q get campus_auth.@auth[0].server_ip || echo "172.20.4.3")
    AUTH_DOMAIN=$(uci -q get campus_auth.@auth[0].auth_domain || echo "auth.gxstnu.edu.cn")
    WAN_DEV=$(uci -q get campus_auth.@auth[0].wan_device || echo "wan")
    WAN_GW=$(uci -q get campus_auth.@auth[0].wan_gateway || echo "172.17.21.1")
    
    # 可配置认证参数
    VLAN=$(uci -q get campus_auth.@auth[0].vlan || echo "0")
    AUTH_TYPE=$(uci -q get campus_auth.@auth[0].auth_type || echo "0")
    IS_BIND_MAC=$(uci -q get campus_auth.@auth[0].isBindMac || echo "0")
    PAGEID=$(uci -q get campus_auth.@auth[0].pageid || echo "5")
    TEMPLATETYPE=$(uci -q get campus_auth.@auth[0].templatetype || echo "1")
    
    # 重试配置
    MAX_RETRY=$(uci -q get campus_auth.@auth[0].max_retry || echo "3")
    RETRY_DELAY=$(uci -q get campus_auth.@auth[0].retry_delay || echo "5")
    AUTH_POLL_MAX=$(uci -q get campus_auth.@auth[0].auth_poll_max || echo "20")
    AUTH_POLL_INTERVAL=$(uci -q get campus_auth.@auth[0].auth_poll_interval || echo "2")
    case "$AUTH_POLL_MAX" in ''|*[!0-9]*) AUTH_POLL_MAX=20 ;; esac
    case "$AUTH_POLL_INTERVAL" in ''|*[!0-9]*) AUTH_POLL_INTERVAL=2 ;; esac
    
    # 通知配置
    DINGTALK_ENABLED=$(uci -q get campus_auth.@notify[0].enabled || echo "0")
    DINGTALK_WEBHOOK=$(uci -q get campus_auth.@notify[0].webhook || echo "")
    DINGTALK_SECRET=$(uci -q get campus_auth.@notify[0].secret || echo "")
}

# 日志函数（自动轮转）
log() {
    local level="$1"
    local msg="$2"
    mkdir -p "$(dirname $LOG_FILE)"
    
    # 日志轮转：超过500行保留最新300行
    [ -f "$LOG_FILE" ] && [ $(wc -l < "$LOG_FILE" 2>/dev/null || echo 0) -gt 500 ] && \
        tail -n 300 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    echo "[$level] $msg"
}

# 钉钉通知（带加签）
send_dingtalk() {
    [ "$DINGTALK_ENABLED" != "1" ] || [ -z "$DINGTALK_WEBHOOK" ] && return 0
    
    local title="$1"
    local content="$2"
    local webhook="$DINGTALK_WEBHOOK"
    
    # 加签处理
    if [ -n "$DINGTALK_SECRET" ]; then
        local timestamp=$(date +%s%3N 2>/dev/null || echo $(date +%s)000)
        local sign=$(echo -ne "${timestamp}\n${DINGTALK_SECRET}" | openssl dgst -sha256 -hmac "$DINGTALK_SECRET" -binary 2>/dev/null | base64 | sed 's/+/%2B/g;s/\//%2F/g;s/=/%3D/g')
        webhook="${webhook}&timestamp=${timestamp}&sign=${sign}"
    fi
    
    local hostname=$(uci -q get system.@system[0].hostname || echo "OpenWrt")
    local time_str=$(date '+%Y-%m-%d %H:%M:%S')
    
    curl -s -X POST "$webhook" \
        -H "Content-Type: application/json" \
        -d "{\"msgtype\":\"markdown\",\"markdown\":{\"title\":\"$title\",\"text\":\"## $title\\n\\n**设备**: ${hostname}\\n**时间**: ${time_str}\\n\\n$content\"}}" \
        >/dev/null 2>&1 &
}

# 获取WAN信息
get_wan_ip() {
    ip -4 addr show "$WAN_DEV" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1 | head -1
}

get_wan_mac() {
    cat /sys/class/net/$WAN_DEV/address 2>/dev/null | tr 'a-f' 'A-F'
}

# 检测认证状态
check_need_auth() {
    local response=$(curl -so /dev/null -w "%{http_code}" \
        --interface "$WAN_DEV" \
        --connect-timeout 3 \
        --max-time 5 \
        "http://connect.rom.miui.com/generate_204" 2>/dev/null)
    
    case "$response" in
        "204") echo "authenticated" ;;
        "302"|"301"|"200") echo "need_auth" ;;
        *) echo "offline" ;;
    esac
}

verify_internet() {
    ping -c1 -W2 -I "$WAN_DEV" 223.5.5.5 >/dev/null 2>&1 && return 0

    local response=$(curl -so /dev/null -w "%{http_code}" \
        --interface "$WAN_DEV" \
        --noproxy "*" \
        --connect-timeout 3 \
        --max-time 5 \
        "http://connect.rom.miui.com/generate_204" 2>/dev/null)

    [ "$response" = "204" ]
}

sanitize_auth_text() {
    printf '%s' "$1" | tr '\r\n' '  ' | sed \
        -e 's/passwd=[^& ]*/passwd=***/g' \
        -e 's/userId=[^& ]*/userId=***/g' \
        -e 's/distoken=[^& ]*/distoken=***/g' \
        -e 's/mac=[^& ]*/mac=***/g' \
        -e 's/wlanuserip=[^& ]*/wlanuserip=***/g' \
        -e 's/"userId"[[:space:]]*:[[:space:]]*"[^"]*"/"userId":"***"/g' \
        | cut -c1-300
}

is_external_dial_pending() {
    printf '%s' "$1" | grep -qiE "正在进行外网|外网[拨拔]号|请稍候|getAuthResult"
}

is_auth_rejected() {
    printf '%s' "$1" | grep -qiE "认证失败|登录失败|密码错误|余额不足|账号异常|fail"
}

poll_auth_result() {
    local account_id="$1"
    local page_id="${2:-5}"
    local attempt=0
    local poll_result=""

    [ -z "$account_id" ] && return 1
    [ "$AUTH_POLL_MAX" -le 0 ] && return 1

    log "INFO" "认证已提交，等待外网拨号结果..."

    while [ "$attempt" -lt "$AUTH_POLL_MAX" ]; do
        attempt=$((attempt + 1))
        sleep "$AUTH_POLL_INTERVAL"

        verify_internet && return 0

        poll_result=$(curl -skS \
            --interface "$WAN_DEV" \
            --noproxy "*" \
            --connect-timeout 5 \
            --max-time 10 \
            --resolve "${AUTH_DOMAIN}:443:${AUTH_SERVER_IP}" \
            -b "$COOKIE_FILE" \
            -c "$COOKIE_FILE" \
            -H "Host: ${AUTH_DOMAIN}" \
            -H "Origin: https://${AUTH_DOMAIN}" \
            -H "Referer: https://${AUTH_DOMAIN}/webauth.do" \
            -H "X-Requested-With: XMLHttpRequest" \
            -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
            --data-urlencode "userId=${account_id}" \
            --data "pageId=${page_id}" \
            "https://${AUTH_DOMAIN}/getAuthResult.do" 2>&1)

        verify_internet && return 0

        if printf '%s' "$poll_result" | grep -qiE "成功|已在线|success|online|LOGINSUCC|true"; then
            sleep 2
            verify_internet && return 0
        fi

        if is_auth_rejected "$poll_result"; then
            log "WARN" "认证轮询返回失败: $(sanitize_auth_text "$poll_result")"
            return 1
        fi

        if [ $((attempt % 5)) -eq 0 ]; then
            log "INFO" "外网拨号仍在处理中 (${attempt}/${AUTH_POLL_MAX})"
        fi
    done

    [ -n "$poll_result" ] && log "WARN" "认证轮询超时，最后响应: $(sanitize_auth_text "$poll_result")"
    return 1
}

# 执行认证（带重试）
do_auth() {
    # 防止并发执行
    [ -f "$LOCK_FILE" ] && [ $(($(date +%s) - $(cat "$LOCK_FILE" 2>/dev/null || echo 0))) -lt 30 ] && {
        log "WARN" "认证进行中，跳过本次请求"
        return 2
    }
    echo $(date +%s) > "$LOCK_FILE"
    
    local ip=$(get_wan_ip)
    local mac=$(get_wan_mac)
    
    [ -z "$ip" ] && {
        log "ERROR" "无法获取WAN IP地址"
        rm -f "$LOCK_FILE"
        return 1
    }
    
    [ -z "$USERNAME" ] && {
        log "ERROR" "未配置认证账号"
        rm -f "$LOCK_FILE"
        return 1
    }
    
    local macl=$(echo "$mac" | tr 'A-Z' 'a-z')
    log "INFO" "===== 开始认证 IP:$ip MAC:$mac ====="
    
    # 添加静态路由
    ip route add "$AUTH_SERVER_IP" via "$WAN_GW" dev "$WAN_DEV" 2>/dev/null || true
    ip route add "$AC_IP" via "$WAN_GW" dev "$WAN_DEV" 2>/dev/null || true
    
    local retry=0
    local success=0
    
    while [ $retry -lt $MAX_RETRY ]; do
        retry=$((retry + 1))
        [ $retry -gt 1 ] && log "INFO" "第 $retry 次重试..."
        
        # 清理旧Cookie
        rm -f "$COOKIE_FILE"
        
        # 获取初始Cookie。先访问BRAS重定向页，确保门户下发的会话字段与当前IP/MAC匹配。
        curl -skL --connect-timeout 5 \
            --max-time 12 \
            --interface "$WAN_DEV" \
            --noproxy "*" \
            --resolve "${AUTH_DOMAIN}:443:${AUTH_SERVER_IP}" \
            -c "$COOKIE_FILE" \
            "http://${AC_IP}/" >/dev/null 2>&1

        curl -sk --connect-timeout 5 \
            --interface "$WAN_DEV" \
            --noproxy "*" \
            --resolve "${AUTH_DOMAIN}:443:${AUTH_SERVER_IP}" \
            -b "$COOKIE_FILE" \
            -c "$COOKIE_FILE" \
            "https://${AUTH_DOMAIN}/" >/dev/null 2>&1
        
        # 构造认证数据（使用可配置参数）
        local data="wlanacip=${AC_IP}&wlanacname=${AC_NAME}&wlanuserip=${ip}&mac=${macl}&vlan=${VLAN}"
        data="${data}&scheme=https&serverIp=tomcat_server1:443&hostIp=http://127.0.0.1:8446/&loginType=&auth_type=${AUTH_TYPE}"
        data="${data}&isBindMac1=${IS_BIND_MAC}&pageid=${PAGEID}&templatetype=${TEMPLATETYPE}&listbindmac=0&recordmac=0&isRemind=1"
        data="${data}&portalVer=0&tservertypeid=axe&realTerminalType=a&operatorastrict=0,1,2,3"
        data="${data}&echostr=&loginTimes=&groupId=&url=http://${AC_IP}&remInfo=on"
        
        # 发送认证请求
        local response=$(curl -sSki \
            --interface "$WAN_DEV" \
            --noproxy "*" \
            --connect-timeout 10 \
            --max-time 30 \
            --resolve "${AUTH_DOMAIN}:443:${AUTH_SERVER_IP}" \
            -b "$COOKIE_FILE" \
            -c "$COOKIE_FILE" \
            -H "Host: ${AUTH_DOMAIN}" \
            -H "Origin: https://${AUTH_DOMAIN}" \
            -H "Referer: https://${AUTH_DOMAIN}/webauth.do" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "$data" \
            --data-urlencode "userId=${USERNAME}" \
            --data-urlencode "passwd=${PASSWORD}" \
            "https://${AUTH_DOMAIN}/webauth.do" 2>&1)
        
        sleep 2
        
        # 验证认证结果
        if verify_internet; then
            log "INFO" "✅ 认证成功 (第 $retry 次尝试)"
            send_dingtalk "✅ 校园网认证成功" "账号: ${USERNAME}\\n重试次数: ${retry}"
            success=1
            break
        fi

        if is_external_dial_pending "$response"; then
            if poll_auth_result "$USERNAME" "$PAGEID"; then
                log "INFO" "✅ 认证成功 (第 $retry 次尝试，外网拨号完成)"
                send_dingtalk "✅ 校园网认证成功" "账号: ${USERNAME}\\n重试次数: ${retry}\\n外网拨号已完成"
                success=1
                break
            fi
            log "WARN" "外网拨号未完成: $(sanitize_auth_text "$response")"
        elif is_auth_rejected "$response"; then
            log "WARN" "认证服务器返回失败: $(sanitize_auth_text "$response")"
        fi
        
        # 检查是否在非上网时段
        if echo "$response" | grep -qiE "不在.*时段|time|时段限制"; then
            log "WARN" "⏰ 不在上网时段，切换备用线路"
            send_dingtalk "⏰ 不在上网时段" "已切换备用线路"
            rm -f "$LOCK_FILE"
            return 2
        fi
        
        [ $retry -lt $MAX_RETRY ] && sleep $RETRY_DELAY
    done
    
    rm -f "$LOCK_FILE"
    
    if [ $success -eq 1 ]; then
        return 0
    else
        log "ERROR" "❌ 认证失败 (已重试 $MAX_RETRY 次)"
        send_dingtalk "❌ 校园网认证失败" "账号: ${USERNAME}\\n已重试 $MAX_RETRY 次\\n请检查账号密码"
        return 1
    fi
}

# mwan3 钩子
mwan3_hook() {
    log "INFO" "mwan3 事件触发检查"
    
    local status=$(check_need_auth)
    case "$status" in
        "authenticated")
            log "INFO" "状态: 已认证"
            ;;
        "need_auth")
            log "INFO" "状态: 需要认证"
            do_auth
            ;;
        "offline")
            log "WARN" "状态: 离线"
            ;;
    esac
}

# 定时任务处理
handle_schedule() {
    case "$1" in
        "midnight")
            log "INFO" "⏰ 执行0点断网操作"
            uci set network.wan.disabled='1'
            uci commit network
            ifdown wan 2>/dev/null || true
            mwan3 ifdown wan 2>/dev/null || true
            send_dingtalk "🌙 0点切换" "校园网已断开，切换备用线路"
            ;;
        "morning")
            log "INFO" "⏰ 执行6点恢复操作"
            uci set network.wan.disabled='0'
            uci commit network
            ifup wan 2>/dev/null || true
            sleep 10
            mwan3 ifup wan 2>/dev/null || true
            sleep 5
            if do_auth; then
                send_dingtalk "☀️ 6点切换" "校园网已启用并完成认证"
            else
                local rc=$?
                local status=$(check_need_auth)
                send_dingtalk "⚠️ 6点切换" "校园网已启用，但认证未成功\n返回码: ${rc}\n当前状态: ${status}"
            fi
            ;;
    esac
}

# 加密密码命令
encrypt_password_cmd() {
    if [ -z "$1" ]; then
        echo "用法: $0 encrypt <密码>"
        return 1
    fi
    local enc=$($SCRIPT_DIR/campus_auth_crypto.sh encrypt "$1")
    uci set campus_auth.@auth[0].password="$enc"
    uci set campus_auth.@auth[0].password_encrypted='1'
    uci commit campus_auth
    echo "✅ 密码已加密保存"
}

# 状态查询
show_status() {
    echo "=========================================="
    echo "  校园网认证状态"
    echo "=========================================="
    echo "WAN IP:    $(get_wan_ip)"
    echo "WAN MAC:   $(get_wan_mac)"
    echo "认证状态:  $(check_need_auth)"
    echo "账号:      $USERNAME"
    echo "=========================================="
    echo "最近日志:"
    tail -10 "$LOG_FILE" 2>/dev/null || echo "暂无日志"
}

# 主入口
load_config

case "$1" in
    login|auth)
        do_auth
        ;;
    check)
        echo $(check_need_auth)
        ;;
    hook)
        mwan3_hook
        ;;
    midnight)
        handle_schedule "midnight"
        ;;
    morning)
        handle_schedule "morning"
        ;;
    status)
        show_status
        ;;
    encrypt)
        encrypt_password_cmd "$2"
        ;;
    test)
        echo "配置测试:"
        echo "  用户名: $USERNAME"
        echo "  认证域: $AUTH_DOMAIN"
        echo "  服务器: $AUTH_SERVER_IP"
        echo "  AC IP:  $AC_IP"
        echo "  最大重试: $MAX_RETRY"
        ;;
    *)
        echo "用法: $0 {login|check|hook|midnight|morning|status|encrypt|test}"
        echo ""
        echo "命令说明:"
        echo "  login    - 执行认证"
        echo "  check    - 检测认证状态"
        echo "  hook     - mwan3事件钩子"
        echo "  midnight - 0点断网"
        echo "  morning  - 6点恢复"
        echo "  status   - 显示状态"
        echo "  encrypt  - 加密保存密码"
        echo "  test     - 测试配置"
        ;;
esac
AUTHEOF

chmod +x /root/campus_auth.sh

# ============================================================
# 5. 配置 mwan3
# ============================================================
echo "📝 配置 mwan3 多线路..."

# 检查mwan3是否安装
if ! opkg list-installed | grep -q "^mwan3 -"; then
    echo "⚠️  mwan3 未安装，正在安装..."
    opkg install mwan3 2>/dev/null || echo "❌ 请手动安装: opkg install mwan3"
fi

# 创建mwan3运行目录
mkdir -p /var/run/mwan3track/wan
mkdir -p /var/run/mwan3track/lan1
mkdir -p /var/run/mwan3track/u20

if [ -s /etc/config/mwan3 ]; then
    cp -a /etc/config/mwan3 "/etc/config/mwan3.bak-campus_auth-$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    echo "✅ 检测到已有 mwan3 配置，已备份并跳过自动覆盖"
else
    cat > /etc/config/mwan3 << 'MWAN3EOF'
config globals 'globals'
    option enabled '1'
    option mmx_mask '0x3F00'

config interface 'wan'
    option enabled '1'
    option family 'ipv4'
    option track_method 'ping'
    list track_ip '223.5.5.5'
    list track_ip '119.29.29.29'
    option reliability '1'
    option count '1'
    option timeout '2'
    option interval '3'
    option failure_interval '1'
    option recovery_interval '3'
    option down '3'
    option up '3'
    option initial_state 'online'

config interface 'lan1'
    option enabled '1'
    option family 'ipv4'
    option track_method 'ping'
    list track_ip '119.29.29.29'
    list track_ip '223.5.5.5'
    option reliability '1'
    option count '1'
    option timeout '2'
    option interval '5'
    option failure_interval '2'
    option recovery_interval '5'
    option down '3'
    option up '3'
    option initial_state 'online'

config interface 'u20'
    option enabled '1'
    option family 'ipv4'
    option track_method 'ping'
    list track_ip '119.29.29.29'
    list track_ip '223.5.5.5'
    option reliability '1'
    option count '1'
    option timeout '3'
    option interval '10'
    option failure_interval '3'
    option recovery_interval '10'
    option down '3'
    option up '3'
    option initial_state 'online'

config member 'wan_m1'
    option interface 'wan'
    option metric '1'
    option weight '10'

config member 'lan1_m1'
    option interface 'lan1'
    option metric '2'
    option weight '10'

config member 'u20_m1'
    option interface 'u20'
    option metric '3'
    option weight '10'

config policy 'failover'
    list use_member 'wan_m1'
    list use_member 'lan1_m1'
    list use_member 'u20_m1'
    option last_resort 'default'

config rule 'default_rule'
    option dest_ip '0.0.0.0/0'
    option proto 'all'
    option sticky '0'
    option use_policy 'failover'
MWAN3EOF
fi

# ============================================================
# 6. 配置 mwan3 Hook
# ============================================================
echo "📝 配置 mwan3 事件钩子..."

cat > /etc/mwan3.user << 'HOOKEOF'
#!/bin/sh
# mwan3 事件钩子 - WAN ifup 后自动检查认证
[ "$INTERFACE" = "wan" ] && [ "$ACTION" = "ifup" ] && {
    sleep 2
    /root/campus_auth.sh hook >/dev/null 2>&1 &
}
HOOKEOF
chmod +x /etc/mwan3.user

# ============================================================
# 7. 配置定时任务
# ============================================================
echo "📝 配置定时任务..."

mkdir -p /etc/crontabs
touch /etc/crontabs/root

# 移除旧配置
sed -i '/campus_auth/d' /etc/crontabs/root 2>/dev/null || true

# 添加新配置
echo "# ========== 校园网智能切换系统计划任务 ==========" >> /etc/crontabs/root
echo "# 如需物理断网策略，请手动添加（默认不强制禁用 WAN）" >> /etc/crontabs/root
echo "0 0 * * * /root/campus_auth.sh midnight >/dev/null 2>&1" >> /etc/crontabs/root
echo "0 6 * * * /root/campus_auth.sh morning >/dev/null 2>&1" >> /etc/crontabs/root
# 每30分钟检查一次认证状态
echo "*/30 * * * * /root/campus_auth.sh hook >/dev/null 2>&1" >> /etc/crontabs/root

# ============================================================
# 8. 安装 LuCI Web 界面
# ============================================================
echo "📝 安装 LuCI Web 界面..."

# Controller
mkdir -p /usr/lib/lua/luci/controller
cat > /usr/lib/lua/luci/controller/campus_auth.lua << 'CTRLEOF'
module("luci.controller.campus_auth", package.seeall)

function index()
    entry({"admin", "services", "campus_auth"}, firstchild(), _("校园网认证"), 60).dependent = false
    entry({"admin", "services", "campus_auth", "status"}, template("campus_auth/status"), _("状态监控"), 10)
    entry({"admin", "services", "campus_auth", "config"}, cbi("campus_auth/config"), _("认证配置"), 20)
    entry({"admin", "services", "campus_auth", "notify"}, cbi("campus_auth/notify"), _("通知设置"), 30)
    entry({"admin", "services", "campus_auth", "logs"}, template("campus_auth/logs"), _("运行日志"), 40)
    
    -- API 端点
    entry({"admin", "services", "campus_auth", "api", "status"}, call("api_status")).leaf = true
    entry({"admin", "services", "campus_auth", "api", "action"}, call("api_action")).leaf = true
    entry({"admin", "services", "campus_auth", "api", "logs"}, call("api_logs")).leaf = true
    entry({"admin", "services", "campus_auth", "api", "mwan3"}, call("api_mwan3")).leaf = true
end

-- 安全过滤函数（防止日志注入）
function safe_filter(str)
    if not str then return "" end
    -- 只允许字母、数字、中文、空格、下划线、横线
    return str:gsub("[^%w%s%-%_%.]", "")
end

function api_status()
    local sys = require "luci.sys"
    local http = require "luci.http"
    local status = {}
    
    -- WAN信息
    status.wan_ip = sys.exec("ip -4 addr show wan 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -1"):gsub("\n", "")
    status.wan_mac = sys.exec("cat /sys/class/net/wan/address 2>/dev/null"):gsub("\n", ""):upper()
    status.wan_gateway = sys.exec("uci -q get campus_auth.@auth[0].wan_gateway"):gsub("\n", "")
    
    -- 认证状态检测
    local code = sys.exec("curl -so /dev/null -w '%{http_code}' --interface wan --connect-timeout 3 --max-time 5 'http://connect.rom.miui.com/generate_204' 2>/dev/null"):gsub("\n", "")
    if code == "204" then
        status.auth_status = "authenticated"
        status.auth_text = "已认证"
        status.auth_color = "#27ae60"
    elseif code == "302" or code == "301" or code == "200" then
        status.auth_status = "need_auth"
        status.auth_text = "需要认证"
        status.auth_color = "#f39c12"
    else
        status.auth_status = "offline"
        status.auth_text = "离线"
        status.auth_color = "#e74c3c"
    end
    
    -- 外网检测
    if sys.call("ping -c 1 -W 2 223.5.5.5 >/dev/null 2>&1") == 0 then
        status.internet = "online"
        status.internet_text = "正常"
        status.internet_color = "#27ae60"
    else
        status.internet = "offline"
        status.internet_text = "断开"
        status.internet_color = "#e74c3c"
    end
    
    -- 账号信息
    status.username = sys.exec("uci -q get campus_auth.@auth[0].username"):gsub("\n", "")
    
    -- 上次认证时间
    status.last_auth = sys.exec("grep '认证成功' /var/log/campus_auth.log 2>/dev/null | tail -1 | cut -d']' -f1 | tr -d '['"):gsub("\n", "")
    if status.last_auth == "" then status.last_auth = "暂无记录" end
    
    -- 系统时间
    status.sys_time = os.date("%Y-%m-%d %H:%M:%S")
    
    -- 当前时段
    local hour = tonumber(os.date("%H"))
    if hour >= 0 and hour < 6 then
        status.period = "夜间断网时段 (0:00-6:00)"
        status.period_color = "#9b59b6"
    else
        status.period = "正常上网时段 (6:00-24:00)"
        status.period_color = "#27ae60"
    end
    
    http.prepare_content("application/json")
    http.write_json(status)
end

function api_action()
    local sys = require "luci.sys"
    local http = require "luci.http"
    local action = http.formvalue("action")
    local result = {success = false, message = ""}
    
    if action == "login" then
        local output = sys.exec("/root/campus_auth.sh login 2>&1")
        if output:match("认证成功") then
            result.success = true
            result.message = "认证成功！"
        else
            result.message = "认证失败：" .. output:sub(1, 200)
        end
    elseif action == "check" then
        local output = sys.exec("/root/campus_auth.sh check 2>&1"):gsub("\n", "")
        result.success = true
        result.message = output
    elseif action == "midnight" then
        sys.exec("/root/campus_auth.sh midnight >/dev/null 2>&1 &")
        result.success = true
        result.message = "已执行0点断网操作"
    elseif action == "morning" then
        sys.exec("/root/campus_auth.sh morning >/dev/null 2>&1 &")
        result.success = true
        result.message = "已执行6点恢复操作"
    elseif action == "restart_wan" then
        sys.exec("ifdown wan && sleep 2 && ifup wan &")
        result.success = true
        result.message = "WAN接口正在重启..."
    else
        result.message = "未知操作"
    end
    
    http.prepare_content("application/json")
    http.write_json(result)
end

function api_logs()
    local sys = require "luci.sys"
    local http = require "luci.http"
    local lines = tonumber(http.formvalue("lines")) or 100
    local filter = safe_filter(http.formvalue("filter") or "")
    
    -- 限制行数范围，防止资源耗尽
    if lines < 1 or lines > 1000 then lines = 100 end
    
    local cmd = "tail -n " .. lines .. " /var/log/campus_auth.log 2>/dev/null"
    if filter ~= "" then
        cmd = "grep -i '" .. filter .. "' /var/log/campus_auth.log 2>/dev/null | tail -n " .. lines
    end
    
    local logs = sys.exec(cmd) or "暂无日志"
    
    http.prepare_content("application/json")
    http.write_json({logs = logs})
end

function api_mwan3()
    local sys = require "luci.sys"
    local http = require "luci.http"
    
    local status = sys.exec("mwan3 status 2>/dev/null") or ""
    local interfaces = {}
    
    -- 解析接口状态
    for iface in status:gmatch("interface ([%w_]+) is online") do
        interfaces[iface] = {status = "online", color = "#27ae60"}
    end
    for iface in status:gmatch("interface ([%w_]+) is offline") do
        interfaces[iface] = {status = "offline", color = "#e74c3c"}
    end
    
    http.prepare_content("application/json")
    http.write_json({raw = status, interfaces = interfaces})
end
CTRLEOF

# CBI Model - 认证配置
mkdir -p /usr/lib/lua/luci/model/cbi/campus_auth
cat > /usr/lib/lua/luci/model/cbi/campus_auth/config.lua << 'CBIEOF'
local m, s, o

m = Map("campus_auth", "校园网认证配置", 
    "配置校园网认证账号和服务器参数。修改后立即生效，无需重启。")

-- 账号设置
s = m:section(NamedSection, "@auth[0]", "auth", "账号设置")
s.anonymous = true
s.addremove = false

o = s:option(Value, "username", "认证账号")
o.placeholder = "输入校园网账号"
o.rmempty = false
o.datatype = "string"

o = s:option(Value, "password", "认证密码")
o.password = true
o.placeholder = "输入校园网密码"
o.rmempty = false
o.description = "密码将以加密形式存储"

-- 服务器设置
s2 = m:section(NamedSection, "@auth[0]", "auth", "服务器设置")
s2.anonymous = true
s2.addremove = false

o = s2:option(Value, "auth_domain", "认证域名")
o.default = "auth.gxstnu.edu.cn"
o.placeholder = "auth.gxstnu.edu.cn"

o = s2:option(Value, "server_ip", "认证服务器IP")
o.default = "172.20.4.3"
o.datatype = "ip4addr"
o.placeholder = "172.20.4.3"
o.description = "认证服务器的真实IP地址（绕过DNS）"

o = s2:option(Value, "wlanacip", "AC网关IP")
o.default = "172.16.1.82"
o.datatype = "ip4addr"
o.placeholder = "172.16.1.82"

o = s2:option(Value, "wlanacname", "AC名称")
o.default = "GXSTNU-BRAS"
o.placeholder = "GXSTNU-BRAS"

-- 接口设置
s3 = m:section(NamedSection, "@auth[0]", "auth", "接口设置")
s3.anonymous = true
s3.addremove = false

o = s3:option(Value, "wan_device", "WAN接口")
o.default = "wan"
o.placeholder = "wan"
o.description = "用于校园网认证的接口名"

o = s3:option(Value, "wan_gateway", "WAN网关")
o.default = "172.17.21.1"
o.datatype = "ip4addr"
o.placeholder = "172.17.21.1"

-- 高级设置
s4 = m:section(NamedSection, "@auth[0]", "auth", "高级设置")
s4.anonymous = true
s4.addremove = false

o = s4:option(Value, "max_retry", "最大重试次数")
o.default = "3"
o.datatype = "uinteger"
o.placeholder = "3"
o.description = "认证失败后的最大重试次数"

o = s4:option(Value, "retry_delay", "重试间隔(秒)")
o.default = "5"
o.datatype = "uinteger"
o.placeholder = "5"
o.description = "每次重试之间的等待时间"

o = s4:option(Value, "auth_poll_max", "拨号结果轮询次数")
o.default = "20"
o.datatype = "uinteger"
o.placeholder = "20"
o.description = "门户返回正在进行外网拨号时，继续查询最终结果的次数"

o = s4:option(Value, "auth_poll_interval", "拨号轮询间隔(秒)")
o.default = "2"
o.datatype = "uinteger"
o.placeholder = "2"
o.description = "查询外网拨号结果的间隔"

return m
CBIEOF

# CBI Model - 通知设置
cat > /usr/lib/lua/luci/model/cbi/campus_auth/notify.lua << 'NOTIFYEOF'
local m, s, o

m = Map("campus_auth", "通知设置", 
    "配置钉钉机器人通知，在认证状态变化时自动推送消息。")

s = m:section(NamedSection, "@notify[0]", "notify", "钉钉机器人")
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", "启用通知")
o.default = "0"
o.rmempty = false

o = s:option(Value, "webhook", "Webhook地址")
o.placeholder = "https://oapi.dingtalk.com/robot/send?access_token=xxx"
o.description = "钉钉机器人的Webhook地址"
o:depends("enabled", "1")

o = s:option(Value, "secret", "加签密钥")
o.password = true
o.placeholder = "SECxxxxxxxx"
o.description = "钉钉机器人的加签密钥（可选）"
o:depends("enabled", "1")

-- 通知事件
s2 = m:section(NamedSection, "@notify[0]", "notify", "通知事件")
s2.anonymous = true

o = s2:option(Flag, "notify_success", "认证成功")
o.default = "1"
o:depends("enabled", "1")

o = s2:option(Flag, "notify_fail", "认证失败")
o.default = "1"
o:depends("enabled", "1")

o = s2:option(Flag, "notify_schedule", "定时切换")
o.default = "1"
o.description = "0点断网和6点恢复时通知"
o:depends("enabled", "1")

return m
NOTIFYEOF

echo "✅ LuCI界面安装完成"

# ============================================================
# 9. 安装 View 模板
# ============================================================
echo "📝 安装视图模板..."

mkdir -p /usr/lib/lua/luci/view/campus_auth

# 状态监控页面
cat > /usr/lib/lua/luci/view/campus_auth/status.htm << 'VIEWEOF'
<%+header%>
<%
local sys = require "luci.sys"
%>
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>校园网认证管理</title>
    <style>
        :root {
            --primary: #3498db; --success: #27ae60; --warning: #f39c12;
            --danger: #e74c3c; --purple: #9b59b6; --dark: #2c3e50; --light: #ecf0f1;
        }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f6fa; margin: 0; padding: 0; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, var(--primary), var(--purple)); color: white; padding: 25px 30px; border-radius: 15px; margin-bottom: 25px; display: flex; justify-content: space-between; align-items: center; }
        .header h1 { margin: 0; font-size: 24px; }
        .header .time { opacity: 0.9; font-size: 14px; }
        .refresh-btn { background: rgba(255,255,255,0.2); border: none; color: white; padding: 8px 16px; border-radius: 8px; cursor: pointer; }
        .refresh-btn:hover { background: rgba(255,255,255,0.3); }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 20px; margin-bottom: 25px; }
        .card { background: white; border-radius: 12px; padding: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.08); }
        .card h3 { margin: 0 0 15px 0; color: var(--dark); font-size: 16px; border-bottom: 2px solid var(--light); padding-bottom: 10px; }
        .item { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #f0f0f0; }
        .item:last-child { border-bottom: none; }
        .label { color: #666; font-size: 14px; }
        .value { font-weight: 600; font-size: 14px; }
        .badge { padding: 4px 12px; border-radius: 20px; font-size: 12px; font-weight: 600; color: white; }
        .interfaces { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 10px; }
        .iface { display: flex; align-items: center; gap: 6px; padding: 6px 12px; background: var(--light); border-radius: 8px; font-size: 13px; }
        .dot { width: 8px; height: 8px; border-radius: 50%; }
        .actions { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 12px; margin-top: 15px; }
        .btn { padding: 15px; border: none; border-radius: 10px; cursor: pointer; font-size: 13px; font-weight: 600; color: white; display: flex; flex-direction: column; align-items: center; gap: 6px; transition: transform 0.2s; }
        .btn:hover { transform: translateY(-2px); }
        .btn:disabled { opacity: 0.6; cursor: not-allowed; transform: none; }
        .btn.primary { background: linear-gradient(135deg, var(--primary), #2980b9); }
        .btn.success { background: linear-gradient(135deg, var(--success), #1e8449); }
        .btn.warning { background: linear-gradient(135deg, var(--warning), #d68910); }
        .btn.danger { background: linear-gradient(135deg, var(--danger), #c0392b); }
        .btn.purple { background: linear-gradient(135deg, var(--purple), #7d3c98); }
        .btn .icon { font-size: 20px; }
        .result { margin-top: 15px; padding: 12px 16px; border-radius: 8px; display: none; }
        .result.show { display: block; }
        .result.success { background: #d4edda; color: #155724; }
        .result.error { background: #f8d7da; color: #721c24; }
        .loading { width: 16px; height: 16px; border: 2px solid rgba(255,255,255,0.3); border-top-color: white; border-radius: 50%; animation: spin 1s linear infinite; display: inline-block; }
        @keyframes spin { to { transform: rotate(360deg); } }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div>
                <h1>🎓 校园网认证管理</h1>
                <div class="time"><span id="sys_time">--</span> | <span id="period" style="padding:2px 8px;border-radius:10px;background:rgba(255,255,255,0.2);">--</span></div>
            </div>
            <button class="refresh-btn" onclick="refreshStatus()">🔄 刷新</button>
        </div>
        <div class="grid">
            <div class="card">
                <h3>📡 认证状态</h3>
                <div class="item"><span class="label">认证状态</span><span class="badge" id="auth_badge" style="background:#ccc;">检测中...</span></div>
                <div class="item"><span class="label">外网连接</span><span class="badge" id="internet_badge" style="background:#ccc;">检测中...</span></div>
                <div class="item"><span class="label">认证账号</span><span class="value" id="username">--</span></div>
                <div class="item"><span class="label">上次认证</span><span class="value" id="last_auth">--</span></div>
            </div>
            <div class="card">
                <h3>🌐 WAN接口</h3>
                <div class="item"><span class="label">IP地址</span><span class="value" id="wan_ip">--</span></div>
                <div class="item"><span class="label">MAC地址</span><span class="value" id="wan_mac">--</span></div>
                <div class="item"><span class="label">网关</span><span class="value" id="wan_gateway">--</span></div>
            </div>
            <div class="card">
                <h3>🔀 mwan3 多线路</h3>
                <div class="interfaces" id="mwan3_interfaces"><span style="color:#999;">加载中...</span></div>
            </div>
        </div>
        <div class="card">
            <h3>⚡ 快捷操作</h3>
            <div class="actions">
                <button class="btn primary" onclick="doAction('login')" id="btn_login"><span class="icon">🔐</span><span>立即认证</span></button>
                <button class="btn success" onclick="doAction('check')" id="btn_check"><span class="icon">🔍</span><span>检测状态</span></button>
                <button class="btn warning" onclick="doAction('restart_wan')" id="btn_restart"><span class="icon">🔄</span><span>重启WAN</span></button>
                <button class="btn purple" onclick="doAction('morning')" id="btn_morning"><span class="icon">☀️</span><span>模拟6点</span></button>
                <button class="btn danger" onclick="doAction('midnight')" id="btn_midnight"><span class="icon">🌙</span><span>模拟0点</span></button>
            </div>
            <div class="result" id="result_box"></div>
        </div>
    </div>
    <script>
    var API='<%=luci.dispatcher.build_url("admin/services/campus_auth/api")%>';
    function refreshStatus(){
        fetch(API+'/status').then(r=>r.json()).then(d=>{
            document.getElementById('sys_time').textContent=d.sys_time;
            document.getElementById('period').textContent=d.period;
            document.getElementById('period').style.background=d.period_color;
            document.getElementById('auth_badge').textContent=d.auth_text;
            document.getElementById('auth_badge').style.background=d.auth_color;
            document.getElementById('internet_badge').textContent=d.internet_text;
            document.getElementById('internet_badge').style.background=d.internet_color;
            document.getElementById('username').textContent=d.username||'--';
            document.getElementById('last_auth').textContent=d.last_auth;
            document.getElementById('wan_ip').textContent=d.wan_ip||'未获取';
            document.getElementById('wan_mac').textContent=d.wan_mac||'--';
            document.getElementById('wan_gateway').textContent=d.wan_gateway||'--';
        }).catch(e=>console.error(e));
        fetch(API+'/mwan3').then(r=>r.json()).then(d=>{
            var html='',ifaces=d.interfaces||{},names={wan:'校园网',lan1:'CPE',u20:'随身WiFi'};
            ['wan','lan1','u20'].forEach(function(i){
                var info=ifaces[i],c=info?info.color:'#999',s=info?(info.status==='online'?'在线':'离线'):'未知';
                html+='<div class="iface"><span class="dot" style="background:'+c+'"></span><span>'+(names[i]||i)+': '+s+'</span></div>';
            });
            document.getElementById('mwan3_interfaces').innerHTML=html||'<span style="color:#999">无数据</span>';
        }).catch(e=>{document.getElementById('mwan3_interfaces').innerHTML='<span style="color:#e74c3c">获取失败</span>';});
    }
    function doAction(a){
        var btn=document.getElementById('btn_'+a.replace('restart_wan','restart')),rb=document.getElementById('result_box');
        if(btn){btn.disabled=true;btn.querySelector('.icon').innerHTML='<span class="loading"></span>';}
        fetch(API+'/action?action='+a).then(r=>r.json()).then(d=>{
            rb.className='result show '+(d.success?'success':'error');rb.textContent=d.message;
            setTimeout(function(){rb.className='result';},5000);setTimeout(refreshStatus,1000);
        }).catch(e=>{rb.className='result show error';rb.textContent='操作失败: '+e.message;})
        .finally(function(){
            if(btn){btn.disabled=false;var icons={login:'🔐',check:'🔍',restart_wan:'🔄',morning:'☀️',midnight:'🌙'};btn.querySelector('.icon').textContent=icons[a]||'⚡';}
        });
    }
    refreshStatus();setInterval(refreshStatus,10000);
    </script>
</body>
</html>
VIEWEOF

# 日志页面
cat > /usr/lib/lua/luci/view/campus_auth/logs.htm << 'LOGEOF'
<%+header%>
<style>
.logs-container { max-width: 1200px; margin: 0 auto; padding: 20px; }
.logs-header { background: linear-gradient(135deg, #2c3e50, #34495e); color: white; padding: 25px; border-radius: 12px; margin-bottom: 20px; }
.logs-header h1 { margin: 0; font-size: 24px; }
.logs-toolbar { display: flex; gap: 15px; margin-bottom: 15px; flex-wrap: wrap; align-items: center; }
.logs-toolbar select, .logs-toolbar input { padding: 10px 15px; border: 1px solid #ddd; border-radius: 8px; font-size: 14px; }
.logs-toolbar button { padding: 10px 20px; background: #3498db; color: white; border: none; border-radius: 8px; cursor: pointer; font-weight: 600; }
.logs-toolbar button:hover { background: #2980b9; }
.logs-content { background: #1e1e1e; color: #d4d4d4; padding: 20px; border-radius: 12px; font-family: Monaco, Consolas, monospace; font-size: 13px; line-height: 1.6; max-height: 600px; overflow: auto; white-space: pre-wrap; word-break: break-all; }
.log-info { color: #6a9955; } .log-warn { color: #dcdcaa; } .log-error { color: #f14c4c; } .log-time { color: #569cd6; }
.logs-stats { display: flex; gap: 20px; margin-bottom: 15px; }
.stat-item { background: white; padding: 15px 25px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
.stat-item .num { font-size: 24px; font-weight: bold; color: #3498db; }
.stat-item .label { font-size: 12px; color: #666; }
</style>
<div class="logs-container">
    <div class="logs-header"><h1>📋 运行日志</h1></div>
    <div class="logs-stats">
        <div class="stat-item"><div class="num" id="stat_total">-</div><div class="label">总日志条数</div></div>
        <div class="stat-item"><div class="num" id="stat_auth" style="color:#27ae60;">-</div><div class="label">认证成功</div></div>
        <div class="stat-item"><div class="num" id="stat_error" style="color:#e74c3c;">-</div><div class="label">错误/失败</div></div>
    </div>
    <div class="logs-toolbar">
        <select id="log_lines"><option value="50">最近50条</option><option value="100" selected>最近100条</option><option value="200">最近200条</option><option value="500">最近500条</option></select>
        <input type="text" id="log_filter" placeholder="过滤关键词..." style="width:200px;">
        <button onclick="loadLogs()">🔍 加载日志</button>
        <button onclick="loadLogs()" style="background:#27ae60;">🔄 刷新</button>
        <button onclick="clearFilter()" style="background:#95a5a6;">✖ 清除过滤</button>
    </div>
    <div class="logs-content" id="logs_content">加载中...</div>
</div>
<script>
var API='<%=luci.dispatcher.build_url("admin/services/campus_auth/api")%>';
function loadLogs(){
    var lines=document.getElementById('log_lines').value,filter=document.getElementById('log_filter').value;
    document.getElementById('logs_content').innerHTML='加载中...';
    fetch(API+'/logs?lines='+lines+'&filter='+encodeURIComponent(filter)).then(r=>r.json()).then(d=>{
        var logs=d.logs||'暂无日志';
        logs=logs.replace(/\[INFO\]/g,'<span class="log-info">[INFO]</span>');
        logs=logs.replace(/\[WARN\]/g,'<span class="log-warn">[WARN]</span>');
        logs=logs.replace(/\[ERROR\]/g,'<span class="log-error">[ERROR]</span>');
        logs=logs.replace(/(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/g,'<span class="log-time">$1</span>');
        document.getElementById('logs_content').innerHTML=logs;
        var arr=(d.logs||'').split('\n');
        document.getElementById('stat_total').textContent=arr.length;
        document.getElementById('stat_auth').textContent=(d.logs.match(/认证成功/g)||[]).length;
        document.getElementById('stat_error').textContent=(d.logs.match(/\[ERROR\]|失败/g)||[]).length;
    }).catch(e=>{document.getElementById('logs_content').innerHTML='加载失败: '+e.message;});
}
function clearFilter(){document.getElementById('log_filter').value='';loadLogs();}
loadLogs();
</script>
<%+footer%>
LOGEOF

# ============================================================
# 10. 清理缓存并重启服务
# ============================================================
echo "🧹 清理LuCI缓存..."
rm -rf /tmp/luci-modulecache/ 2>/dev/null
rm -rf /tmp/luci-indexcache 2>/dev/null
rm -rf /var/luci-modulecache/ 2>/dev/null

echo "🔄 重启服务..."
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true
/etc/init.d/mwan3 restart 2>/dev/null || true
/etc/init.d/cron restart 2>/dev/null || true

echo ""
echo "=========================================="
echo "✅ 校园网认证系统安装完成！"
echo "=========================================="
echo ""
echo "📌 访问路径: LuCI → 服务 → 校园网认证"
echo "📌 如果看不到菜单，请清除浏览器缓存 (Ctrl+F5)"
echo ""
echo "📝 快速配置:"
echo "   1. 设置账号: uci set campus_auth.@auth[0].username='你的账号'"
echo "   2. 设置密码: uci set campus_auth.@auth[0].password='你的密码'"
echo "   3. 加密密码: /root/campus_auth.sh encrypt '你的密码'"
echo "   4. 保存配置: uci commit campus_auth"
echo ""
echo "📝 常用命令:"
echo "   立即认证: /root/campus_auth.sh login"
echo "   检查状态: /root/campus_auth.sh status"
echo "   加密密码: /root/campus_auth.sh encrypt '密码'"
echo ""
echo "✅ 安装完成！"
