# 认证页面探测说明

本文记录对 GXSTNU 校园网 Portal 认证页面的低影响探测结论，用于指导后续维护。文档只记录字段类型和行为，不保存账号、密码、MAC、IP、`distoken` 等敏感值。

## 页面链路

访问 AC/BRAS 地址：

```text
http://172.16.1.82/
```

会返回 302，服务端标识为：

```text
Server: axe_bras/1.0
```

跳转目标是：

```text
https://auth.gxstnu.edu.cn/webauth.do?... 
```

跳转 query 中会包含：

```text
wlanacip
wlanacname
wlanuserip
mac
vlan
act
distoken
errorMsg
url
```

其中 `distoken`、`mac`、`wlanuserip` 属于会话/终端相关敏感字段，日志中必须脱敏。

## 页面关键行为

认证页标题为“网络认证”，页面隐藏字段中可以看到：

```text
scheme=https
serverIp=tomcat_server1:443
hostIp=http://127.0.0.1:8446/
auth_type=0
pageid=5
templatetype=1
portalVer=0
tservertypeid=axe
realTerminalType=a
operatorastrict=0,1,2,3
```

页面 JS 的普通登录逻辑会把表单提交到：

```text
/webauth.do?<urlParameter>
```

这里的 `urlParameter` 来自 BRAS 跳转 query。

另外，页面存在一个重要的延迟状态：

```text
act=LOGINSUCC
errorMsg=正在进行外网拨号请稍候...
```

这表示门户登录请求已被接受，但外网拨号尚未完成。页面 JS 会每 2 秒请求一次：

```text
POST /getAuthResult.do
```

提交参数为：

```text
userId=<账号>
pageId=5
```

最多轮询 20 次。返回 JSON 中的 `check` 字段如果仍然包含“正在进行外网拨号请稍候”，页面继续等待；如果返回内容包含“成功”，页面会进入后续跳转逻辑。

## 当前插件取舍

当前插件默认不依赖 `urlParameter` 或 `distoken`，原因是：

- 当前简化 POST 已经可以完成认证。
- `urlParameter` 和 `distoken` 是动态会话字段，默认依赖它们会增加过期、缺失、日志泄露和 BRAS 跳转异常的风险。
- 认证失败的主要已知问题不是“提交不够像浏览器”，而是“提交后外网拨号仍在处理中”。

因此当前默认路径只保留确定有收益的改动：

- 继续使用简洁的 `webauth.do` POST。
- 账号和密码使用 `--data-urlencode`，避免特殊字符破坏表单。
- 如果认证响应出现“正在进行外网拨号”，轮询 `getAuthResult.do`，再判断最终外网连通性。
- 对日志中的账号、密码、MAC、IP、`distoken` 等字段做脱敏。

## 什么时候再考虑 `urlParameter/distoken`

只有出现以下证据时，才建议把 `urlParameter/distoken` 做成可选兼容开关：

- 简洁 POST 不再能认证，但浏览器页面可以认证。
- 认证响应明确提示会话无效、token 缺失、参数不完整。
- 抓包确认服务器强依赖 query 中的 `distoken` 或完整 `urlParameter`。
- 不同校区、不同 BRAS 固件导致简洁 POST 行为不一致。

可选实现方向：

```sh
# 只示意，不是当前默认逻辑
url_parameter="$(curl -sk -D - -o /dev/null "http://${AC_IP}/" \
  | tr -d '\r' \
  | sed -n 's/^Location: .*webauth.do?//Ip' \
  | head -1)"

auth_url="https://${AUTH_DOMAIN}/webauth.do"
[ -n "$url_parameter" ] && auth_url="${auth_url}?${url_parameter}"
```

注意事项：

- 不要把完整 `url_parameter` 原样写入日志。
- 不要缓存 `distoken`，它应该按本次认证会话重新获取。
- 部分 BRAS 对 `HEAD` 请求不一定返回完整跳转，获取 `Location` 时更稳妥的是普通 GET 加 `-D - -o /dev/null`。
- 该逻辑应做成可配置开关，而不是替代默认认证路径。

## 不建议纳入自动认证的接口

页面还包含以下接口或链接：

```text
/wechatAuth.do
/quickAuthShare.do
/webdisconn.do
/httpservice/appoffline.do
/self/onlineCharge.do
/self/toChangeGroup.do
/self/toChangeOperator.do
/self/toRemoveMac.do
```

这些主要用于微信认证、临时认证、下线、自助缴费、套餐变更、解绑 MAC 等页面功能。它们不是自动登录主路径的一部分，放进认证脚本会增加误触和维护风险。
