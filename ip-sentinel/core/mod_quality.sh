#!/bin/bash
# ==========================================================
# IP-Sentinel: 深海声呐 (IP 质量全维异步检测模块)
# 核心功能: 动态路由寻路、第三方 API 容灾获取、流媒体解锁链路剖析
# ==========================================================

source /opt/ip_sentinel/config.conf

# ==========================================================
# 1. 动态网络锚定与协议自适应
# 专为多 IP 站群与 NAT 架构设计，确保探针流量精准路由
# ==========================================================
DYNAMIC_IP_PREF="${IP_PREF:-4}"
PROBE_ARGS=("-y" "-j" "-f") # 默认注入: 自动确认、JSON格式、明文无掩码IP

# [强壮正则] 支持 V4, V6 以及带有 [] 护甲的 V6 寻址
if [[ -n "$BIND_IP" && "$BIND_IP" =~ ^[0-9a-fA-F:\[\]\.]+$ ]]; then
    RAW_BIND_IP=$(echo "$BIND_IP" | tr -d '[]')
    # 严格探测物理网卡/虚拟 IP 存活状态，防止 IP 漂移导致探针彻底报错
    if ip addr show 2>/dev/null | grep -qw "$RAW_BIND_IP"; then
        # 挂载原生出网网卡
        PROBE_ARGS+=("-i" "$RAW_BIND_IP")
        
        # 智能识别 V4 / V6，强制覆盖系统默认的 IP_PREF
        if [[ "$RAW_BIND_IP" == *":"* ]]; then
            DYNAMIC_IP_PREF="6"
        elif [[ "$RAW_BIND_IP" == *"."* ]]; then
            DYNAMIC_IP_PREF="4"
        fi
    fi
fi

# 补齐协议版本参数 (-4 或 -6)
PROBE_ARGS+=("-${DYNAMIC_IP_PREF}")

# ----------------------------------------------------------
# 2. 智能拉取引擎 (防 RCE 与 文件防伪校验)
# ----------------------------------------------------------
PROBE_SCRIPT="/opt/ip_sentinel/core/ip_probe.sh"

# [完整性校验] 验证本地残留脚本是否损坏 (防止因被墙或拦截导致本地缓存了无效的 HTML 报错页)
if [ -f "$PROBE_SCRIPT" ] && ! grep -q "xykt" "$PROBE_SCRIPT" 2>/dev/null; then
    rm -f "$PROBE_SCRIPT"
fi

if [ ! -s "$PROBE_SCRIPT" ]; then
    # [首选防线] 严格遵守从官方主干拉取，捍卫纯净底线
    curl -sL -m 10 "https://raw.githubusercontent.com/xykt/IPQuality/main/ip.sh" -o "$PROBE_SCRIPT" 2>/dev/null
    
    # [文件防伪校验] 剔除因解析失效返回的污染文本，并降级至双栈 CDN 节点兜底
    if ! grep -q "xykt" "$PROBE_SCRIPT" 2>/dev/null; then
        rm -f "$PROBE_SCRIPT" 2>/dev/null
        curl -sL -m 15 "https://IP.Check.Place" -o "$PROBE_SCRIPT" 2>/dev/null
    fi
    chmod +x "$PROBE_SCRIPT" 2>/dev/null
fi

# ==========================================================
# 3. 极速预检与容灾打靶系统
# ==========================================

# 封装链路预检函数 (4秒极速探路，拒绝死等阻塞)
preflight_check() {
    local curl_args=("-s" "-m" "4")
    # 提取网卡和协议约束
    for ((i=1; i<=$#; i++)); do
        if [[ "${!i}" == "-i" ]]; then
            local next=$((i+1))
            curl_args+=("--interface" "${!next}")
        elif [[ "${!i}" == "-4" ]]; then
            curl_args+=("-4")
        elif [[ "${!i}" == "-6" ]]; then
            curl_args+=("-6")
        fi
    done
    # 验证该路由设置是否能成功连通外部网络
    curl "${curl_args[@]}" "https://www.cloudflare.com/cdn-cgi/trace" >/dev/null 2>&1
    return $?
}

# [寻路雷达] 阶梯式探测，保证在极端环境下的探针连通性
FINAL_ARGS=()
if preflight_check "${PROBE_ARGS[@]}"; then
    # 阶梯 0: 原定参数 (带 BIND_IP 和协议) 通畅
    FINAL_ARGS=("${PROBE_ARGS[@]}")
else
    # 阶梯 1: 剥离物理网卡限制，只保留协议限制
    FALLBACK_ARGS=("-y" "-j" "-${DYNAMIC_IP_PREF}")
    if preflight_check "${FALLBACK_ARGS[@]}"; then
        FINAL_ARGS=("${FALLBACK_ARGS[@]}")
    else
        # 阶梯 2: 终极裸跑 (不限网卡，不限协议)
        FINAL_ARGS=("-y" "-j")
    fi
fi

# ==========================================================
# 4. 终极实弹打靶与情报萃取
# ==========================================================

# 确保连通性后执行探测，放宽超时阈值以给予第三方 API 充足响应时间
RAW_OUTPUT=$(timeout 300 bash "$PROBE_SCRIPT" "${FINAL_ARGS[@]}" 2>/dev/null)
JSON_DATA="{${RAW_OUTPUT#*\{}"
ESC=$(printf '\033')
JSON_DATA=$(printf "%s" "$JSON_DATA" | sed -e "s/${ESC}\[[0-9;]*[a-zA-Z]//g" -e "s/${ESC}[0-9;]*[a-zA-Z]//g" -e "s/x1b\\[[0-9;]*[a-zA-Z]//g" -e "s/x1b[0-9;]*[a-zA-Z]//g")
IP_ADDR=$(echo "$JSON_DATA" | jq -r '.Head.IP // empty' 2>/dev/null)

if [ -z "$IP_ADDR" ]; then
    curl -s -X POST "${TG_API_URL}" \
        -d "chat_id=${CHAT_ID}" \
        -d "parse_mode=Markdown" \
        -d "text=❌ *深海声呐探测失败*
📍 节点：\`${NODE_ALIAS}\`
🌐 锁定IP：\`${PUBLIC_IP}\`
⚠️ *未收到有效回波。检测源超时或数据解析受阻。*" >/dev/null
    exit 1
fi

ASN=$(echo "$JSON_DATA" | jq -r '.Info.ASN // "Unknown"' 2>/dev/null)
ORG=$(echo "$JSON_DATA" | jq -r '.Info.Organization // "Unknown"' 2>/dev/null)
CITY=$(echo "$JSON_DATA" | jq -r '.Info.City.Name // "Unknown"' 2>/dev/null)
COUNTRY=$(echo "$JSON_DATA" | jq -r '.Info.Region.Name // "Unknown"' 2>/dev/null)
IP_TYPE=$(echo "$JSON_DATA" | jq -r '.Info.Type // "未知属性"' 2>/dev/null)
USAGE_TYPE=$(echo "$JSON_DATA" | jq -r '.Type.Usage.IPinfo // "未知场景"' 2>/dev/null)

# ----------------------------------------------------------
# 深度欺诈与信用评估 (各大权威库联查)
# ----------------------------------------------------------
SCAM_SCORE=$(echo "$JSON_DATA" | jq -r '.Score.SCAMALYTICS // "0"' 2>/dev/null)
ABUSE_SCORE=$(echo "$JSON_DATA" | jq -r '.Score.AbuseIPDB // "0"' 2>/dev/null)
IPQS_SCORE=$(echo "$JSON_DATA" | jq -r '.Score.IPQS // "0"' 2>/dev/null)
IP2L_SCORE=$(echo "$JSON_DATA" | jq -r '.Score.IP2LOCATION // "0"' 2>/dev/null)
FRAUD_RISK=$(echo "$JSON_DATA" | jq -r '.Score.ipapi // "0%"' 2>/dev/null)

# [数据清洗] 过滤 API 阻断带来的空值，确保面板展示整洁
[ "$SCAM_SCORE" == "null" ] || [ -z "$SCAM_SCORE" ] && SCAM_SCORE="N/A"
[ "$ABUSE_SCORE" == "null" ] || [ -z "$ABUSE_SCORE" ] && ABUSE_SCORE="N/A"
[ "$IPQS_SCORE" == "null" ] || [ -z "$IPQS_SCORE" ] && IPQS_SCORE="N/A"
[ "$IP2L_SCORE" == "null" ] || [ -z "$IP2L_SCORE" ] && IP2L_SCORE="N/A"
[ "$FRAUD_RISK" == "null" ] || [ -z "$FRAUD_RISK" ] && FRAUD_RISK="N/A"

# [代理特征嗅探] 识别商业 VPN 或代理痕迹
IS_PROXY="🟢 干净"
if echo "$JSON_DATA" | jq -e '.Factor.Proxy | to_entries | any(.value == true)' >/dev/null 2>&1 || \
   echo "$JSON_DATA" | jq -e '.Factor.VPN | to_entries | any(.value == true)' >/dev/null 2>&1; then
    IS_PROXY="🟡 疑似代理/VPN"
fi

# ----------------------------------------------------------
# 提取流媒体与 AI 解锁指标
# ----------------------------------------------------------
parse_media() {
    local status=$(echo "$JSON_DATA" | jq -r ".Media.$1.Status // \"未知\"" 2>/dev/null)
    local reg=$(echo "$JSON_DATA" | jq -r ".Media.$1.Region // \"\"" 2>/dev/null)
    local type=$(echo "$JSON_DATA" | jq -r ".Media.$1.Type // \"\"" 2>/dev/null)
    
    if [[ "$status" == *"解锁"* ]]; then
        echo "🟢 ${reg} (${type})"
    elif [[ "$status" == *"仅"* ]] || [[ "$status" == *"机房"* ]] || [[ "$status" == *"待支持"* ]]; then
        # 捕捉 Netflix "仅自制"、ChatGPT "仅网页"、TikTok "机房" 等半残缺状态
        echo "🟡 ${status} ${reg}"
    elif [[ "$status" == *"屏蔽"* ]] || [[ "$status" == *"失败"* ]] || [[ "$status" == *"中国"* ]] || [[ "$status" == *"禁"* ]]; then
        # 捕捉高危风控状态
        echo "🔴 ${status}"
    else
        echo "⚪ ${status}"
    fi
}

NF_STAT=$(parse_media "Netflix")
YT_STAT=$(parse_media "Youtube")
DP_STAT=$(parse_media "DisneyPlus")
TK_STAT=$(parse_media "TikTok")
GPT_STAT=$(parse_media "ChatGPT")
APV_STAT=$(parse_media "AmazonPrimeVideo")

# 提取原生 JSON 原始状态用于底层隐写回传
RAW_NF_STAT=$(echo "$JSON_DATA" | jq -r '.Media.Netflix.Status // "Unknown"' 2>/dev/null)
RAW_YT_REG=$(echo "$JSON_DATA" | jq -r '.Media.Youtube.Region // ""' 2>/dev/null)
RAW_YT_STAT=$(echo "$JSON_DATA" | jq -r '.Media.Youtube.Status // "Unknown"' 2>/dev/null)

# ----------------------------------------------------------
# 邮局连通性与黑名单污染度
# ----------------------------------------------------------
PORT25=$(echo "$JSON_DATA" | jq -r '.Mail.Port25 // "false"' 2>/dev/null)
[ "$PORT25" == "true" ] && P25_TEXT="✅ 畅通" || P25_TEXT="❌ 封堵"
DNS_BLACK=$(echo "$JSON_DATA" | jq -r '.Mail.DNSBlacklist.Blacklisted // "0"' 2>/dev/null)
DNS_MARK=$(echo "$JSON_DATA" | jq -r '.Mail.DNSBlacklist.Marked // "0"' 2>/dev/null)

# [送中逻辑判定] 基于核心指标一票否决
WARNING_MSG=""
if [[ "$RAW_YT_REG" == "CN" ]] || [[ "$RAW_YT_STAT" == *"中国"* ]]; then
    # 采用 Bash 扩展转义，避免直接打印字面换行符
    WARNING_MSG=$'\n🚨 **[高危] 该节点已被 Google 判定为中国大陆 (送中)！**\n'
fi

# ==========================================================
# 5. 组装情报级 Markdown 战报与回调构造
# ==========================================================
LOCAL_VER="${AGENT_VERSION:-未知}"
CURRENT_TIME=$(date -u "+%Y-%m-%d %H:%M:%S UTC")

# 强制使用中枢下发的真实 IP 拼接，以防探针星号掩码导致直达链接失效
LINK_IP=$(echo "$PUBLIC_IP" | tr -d '[]')

REPORT="🎯 *IP-Sentinel 深海声呐报告*
📍 节点：\`${NODE_ALIAS}\`
🌐 地址：\`${IP_ADDR}\`${WARNING_MSG}

*🏢 物理身份与网络属性*
\`AS${ASN}\` | \`${ORG}\`
**定位:** \`${COUNTRY} - ${CITY}\`
**属性:** \`${IP_TYPE}\` | \`${USAGE_TYPE}\`
**探针:** ${IS_PROXY}

*🛡️ 欺诈雷达 (0为最优)*
• **Scamalytics:** \`${SCAM_SCORE}/100\`
• **AbuseIPDB:** \`${ABUSE_SCORE}/100\`
• **IPQS:** \`${IPQS_SCORE}/100\`
• **IP2Location:** \`${IP2L_SCORE}/100\`
• **IPAPI 风险率:** \`${FRAUD_RISK}\`

*🎬 核心业务解锁*
• **YouTube:** ${YT_STAT}
• **Netflix:** ${NF_STAT}
• **Disney+:** ${DP_STAT}
• **PrimeVideo:** ${APV_STAT}
• **TikTok:** ${TK_STAT}
• **ChatGPT:** ${GPT_STAT}

*✉️ 邮局与污染度*
• **25 端口出站:** ${P25_TEXT}
• **DNS 污染库:** 严重 \`${DNS_BLACK}\` | 轻微 \`${DNS_MARK}\`

_👉 [🔍 详细信用图谱直达 (Scamalytics)](https://scamalytics.com/ip/${LINK_IP})_

⏱️ \`${CURRENT_TIME}\` | ⚙️ \`v${LOCAL_VER}\`"

# [核心数据萃取] 剥离非数字残留，确保传给 Master 趋势数据库的纯净性
SAFE_SCAM_SCORE=$(echo "$SCAM_SCORE" | tr -cd '0-9')
[ -z "$SAFE_SCAM_SCORE" ] && SAFE_SCAM_SCORE="0"

# 提取 Google(基于YouTube) 和 ChatGPT 的原生状态
RAW_GOOG_STAT="${RAW_YT_REG:-$RAW_YT_STAT}"
[ -z "$RAW_GOOG_STAT" ] && RAW_GOOG_STAT="未知"
RAW_GPT_STAT=$(echo "$JSON_DATA" | jq -r '.Media.ChatGPT.Status // "未知"' 2>/dev/null)

# 废除可能导致中文字符截断乱码的强制限制，改用去隐形换行符的安全传递策略
S_GOOG=$(echo "$RAW_GOOG_STAT" | tr -d '\n\r ')
S_NF=$(echo "$RAW_NF_STAT" | tr -d '\n\r ')
S_GPT=$(echo "$RAW_GPT_STAT" | tr -d '\n\r ')
CB_DATA="svq|${NODE_NAME}|${SAFE_SCAM_SCORE}|${S_GOOG}|${S_NF}|${S_GPT}"

# 挂载内联键盘并直送指挥部
JSON_PAYLOAD=$(jq -n \
  --arg cid "$CHAT_ID" \
  --arg txt "$REPORT" \
  --arg cb "$CB_DATA" \
  --arg cb_manage "manage:${NODE_NAME}" \
  '{
    chat_id: $cid,
    text: $txt,
    parse_mode: "Markdown",
    disable_web_page_preview: true,
    reply_markup: {
      inline_keyboard: [
        [{text: "📥 将本次体检录入趋势库", callback_data: $cb}],
        [{text: "⚙️ 调出该节点控制台", callback_data: $cb_manage}]
      ]
    }
  }')

curl -s -X POST "${TG_API_URL}" -H "Content-Type: application/json" -d "$JSON_PAYLOAD" >/dev/null