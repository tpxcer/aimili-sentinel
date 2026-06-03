#!/bin/bash

# ==========================================================
# 脚本名称: mod_google.sh
# 核心功能: 区域网络模拟、行为轨迹拉伸、地理定位锚定
# ==========================================================

MODULE_NAME="Google"
CONFIG_FILE="/opt/ip_sentinel/config.conf"

# --- [环境预载] ---
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "配置文件丢失！退出执行。"
    exit 1
fi

# [容灾机制] 若宿主环境未注入日志函数，则启动 Fallback 接管
if ! type log >/dev/null 2>&1; then
    log() {
        # [版本锚定] 提取运行时动态版本标识
        local local_ver="${AGENT_VERSION:-未知}"
        
        mkdir -p "${INSTALL_DIR}/logs"
    
        # [时区对齐] 强制采用绝对 UTC 时间消除跨域日志偏移
        local core_msg=$(printf "[v%-5s] [%-5s] [%-7s] [%s] %s" "$local_ver" "$2" "$1" "$REGION_CODE" "$3")
        echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $core_msg" >> "${INSTALL_DIR}/logs/sentinel.log"

        # [系统挂载] 桥接至 Systemd Journal 守护日志
        if command -v logger >/dev/null 2>&1; then
            logger -t ip-sentinel "$core_msg"
        else
            echo "$core_msg"
        fi
    }
fi

log "$MODULE_NAME" "START" "========== 唤醒网络模拟器 [区域: $REGION_NAME] =========="

# --- [数据装配] ---
UA_FILE="${INSTALL_DIR}/data/user_agents.txt"
KW_FILE="${INSTALL_DIR}/data/keywords/kw_${REGION_CODE}.txt"

if [ ! -f "$UA_FILE" ] || [ ! -f "$KW_FILE" ]; then
    log "$MODULE_NAME" "ERROR" "热数据缺失，请检查 data 目录。放弃本次执行。"
    exit 1
fi

mapfile -t UA_POOL < <(grep -v '^$' "$UA_FILE")
mapfile -t KEYWORDS < <(grep -v '^[[:space:]]*$' "$KW_FILE")

# [v4.1.5 修复] 防止关键词池为空导致 RANDOM % 0 直接语法崩溃
if [ ${#KEYWORDS[@]} -eq 0 ]; then
    log "$MODULE_NAME" "ERROR" "关键词池为空，终止执行。"
    exit 1
fi

# --- [辅助运算] ---
get_random_coord() {
    local base=$1
    local range=$2 
    local offset=$(awk "BEGIN {print ( ( ($RANDOM % ($range * 2)) - $range ) / 10000 )}")
    awk "BEGIN {print ($base + $offset)}"
}

# --- [身份画像构建] ---
# [防线提取] 优先捕获固化的公网面孔作为种子
CURRENT_IP="${PUBLIC_IP:-${BIND_IP:-Unknown}}"

# -----------------------------------------------------------
# [指纹固化] 哈希锚定法 (Hash-Seeded Persona)
# 基于 IP 算力固定会话指纹池，彻底破除僵尸网络同质化特征
# -----------------------------------------------------------
TOTAL_UA=${#UA_POOL[@]}
if [ "$TOTAL_UA" -gt 0 ]; then
    SEED=$(echo -n "$CURRENT_IP" | cksum | awk '{print $1}')
    
    IDX1=$(( SEED % TOTAL_UA ))
    IDX2=$(( (SEED * 17) % TOTAL_UA ))
    IDX3=$(( (SEED * 31) % TOTAL_UA ))
    
    MY_UA_POOL=("${UA_POOL[$IDX1]}" "${UA_POOL[$IDX2]}" "${UA_POOL[$IDX3]}")
    SESSION_UA=${MY_UA_POOL[$RANDOM % 3]}
else
    # [极简兜底] 降维指纹防御崩溃
    SESSION_UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
fi

# -----------------------------------------------------------
# [v4.1.4 平台身份提取器 (Persona Mapper)]
# 识别当前指纹的系统平台，杜绝跨平台的底层探针穿帮
# -----------------------------------------------------------
UA_PLATFORM="windows"
if [[ "$SESSION_UA" == *"Android"* ]]; then
    UA_PLATFORM="android"
elif [[ "$SESSION_UA" == *"iPhone"* ]] || [[ "$SESSION_UA" == *"iPad"* ]]; then
    UA_PLATFORM="ios"
elif [[ "$SESSION_UA" == *"Macintosh"* ]]; then
    UA_PLATFORM="macos"
elif [[ "$SESSION_UA" == *"Linux"* ]]; then
    UA_PLATFORM="linux"
fi

# [v4.1.5 防御] 坐标缺失直接终止，禁止生成错误地理画像
if ! [[ "$BASE_LAT" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || \
   ! [[ "$BASE_LON" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
    log "$MODULE_NAME" "ERROR" "区域坐标缺失或非法，拒绝执行本轮会话。"
    exit 1
fi

# [LBS 锚定] 在基准战区内生成固定范围内的微抖动咖啡馆坐标
SESSION_BASE_LAT=$(get_random_coord $BASE_LAT 270)
SESSION_BASE_LON=$(get_random_coord $BASE_LON 270)

# 【核心升级】随机决定本次上网深度 (5 - 8 个复合动作，配合高频长效拉伸)
TOTAL_ACTIONS=$((5 + RANDOM % 4))

log "$MODULE_NAME" "INFO " "当前出网 IP: $CURRENT_IP"
log "$MODULE_NAME" "INFO " "设备指纹锁定: ${SESSION_UA:0:45}..."
log "$MODULE_NAME" "INFO " "平台推断: [$UA_PLATFORM] "
log "$MODULE_NAME" "INFO " "虚拟驻留坐标: $SESSION_BASE_LAT, $SESSION_BASE_LON"

# -----------------------------------------------------------
# [v4.1.2] Cookie 持久化身份库 (Google 专属物理隔离)
# 构建真实的 Session 连续性，打破“每分钟失忆”的机器人特征
# -----------------------------------------------------------
COOKIE_DIR="${INSTALL_DIR}/data/cookies"
mkdir -p "$COOKIE_DIR"

NODE_HASH=$(echo -n "$CURRENT_IP" | cksum | awk '{print $1}')
COOKIE_FILE="${COOKIE_DIR}/google_${NODE_HASH}.txt"

# [互斥锁] 防止会话重叠导致的 Cookie 文件读写冲突
LOCK_FILE="${COOKIE_FILE}.lock"
exec 200>"$LOCK_FILE"
flock -n 200 || {
    log "$MODULE_NAME" "WARN " "检测到已有 Google 会话运行，跳过本轮。"
    exit 0
}

# [v4.1.2 磁盘防御] 定期清理超过 14 天的废弃 Cookie，防止长期挂机导致 I/O 拥堵
find "$COOKIE_DIR" -type f -name "google_*.txt" -mtime +14 -delete 2>/dev/null || true

log "$MODULE_NAME" "INFO " "Cookie 身份库已挂载: ${COOKIE_FILE}"

# -----------------------------------------------------------
# [网络栈探底] 协议自适应与出站死锁
# -----------------------------------------------------------
CURL_BIND_ARGS=()
DYNAMIC_IP_PREF="-${IP_PREF:-4}"

if [[ -n "$BIND_IP" && "$BIND_IP" =~ ^[0-9a-fA-F:\.]+$ ]]; then
    # [防线校验] 探测物理网卡存活状态，防 IP 漂移引发通信雪崩
    RAW_BIND_IP=$(echo "$BIND_IP" | tr -d '[]')
    # [v4.1.5 修复] 使用 -Fq 替代 -qw，防止 IPv6 冒号被误认为单词边界导致网卡死锁失效
    if ! ip addr show 2>/dev/null | grep -Fq "$RAW_BIND_IP"; then
    log "$MODULE_NAME" "WARN " "检测到配置的出口 IP ($RAW_BIND_IP) 已丢失，自动降级为系统默认路由出网！"
    CURL_BIND_ARGS=()
    else
        CURL_BIND_ARGS=(--interface "$BIND_IP")
        if [[ "$BIND_IP" == *":"* ]]; then
            DYNAMIC_IP_PREF="-6"
            log "$MODULE_NAME" "INFO " "底层路由锁定: 绑定 IPv6 出口及协议 ($BIND_IP)"
        elif [[ "$BIND_IP" == *"."* ]]; then
            DYNAMIC_IP_PREF="-4"
            log "$MODULE_NAME" "INFO " "底层路由锁定: 绑定 IPv4 出口及协议 ($BIND_IP)"
        fi
    fi
fi

# [v4.1.5 修复] 业务域 Referer 隔离池初始化
# 防止出现从 Apple 探针直接跳转到 Google Maps 的反人类机器行为
REF_SEARCH=""
REF_NEWS=""
REF_MAPS=""
REF_ECO=""

# --- [会话漫游模拟] ---
for ((i=1; i<=TOTAL_ACTIONS; i++)); do
    # [LBS 微抖动] 模拟人类手持设备时的 GPS 细微漂移
    ACTION_LAT=$(get_random_coord $SESSION_BASE_LAT 1)
    ACTION_LON=$(get_random_coord $SESSION_BASE_LON 1)
    
    RAND_KEY="${KEYWORDS[$((RANDOM % ${#KEYWORDS[@]}))]}"
        # [v4.1.6 修复] jq 缺失时自动降级为纯文本编码，防止关键词池熵塌缩
    if command -v jq >/dev/null 2>&1; then
        ENCODED_KEY=$(printf '%s' "$RAND_KEY" | jq -sRr @uri 2>/dev/null)
    else
        ENCODED_KEY=$(printf '%s' "$RAND_KEY" | sed 's/ /+/g')
    fi

    [ -z "$ENCODED_KEY" ] && ENCODED_KEY=$(printf '%s' "$RAND_KEY" | tr ' ' '+')
    
    # [v4.1.4] 平台级动作轮盘：基于 UA_PLATFORM 构建专属行为矩阵
    ACTION_DICE=$((RANDOM % 100))
    TARGET_URL=""
    ACTION_LOG=""

    if [ "$UA_PLATFORM" == "android" ]; then
        if [ $ACTION_DICE -lt 25 ]; then
            TARGET_URL="https://www.google.com/search?q=${ENCODED_KEY}&${LANG_PARAMS}"
            ACTION_LOG="Search "
        elif [ $ACTION_DICE -lt 55 ]; then
            TARGET_URL="https://news.google.com/home?${LANG_PARAMS}"
            ACTION_LOG="News   "
        elif [ $ACTION_DICE -lt 85 ]; then
            TARGET_URL="https://www.google.com/maps/search/${ENCODED_KEY}/@${ACTION_LAT},${ACTION_LON},17z?${LANG_PARAMS}"
            ACTION_LOG="Maps   "
        else
            # Android 专属底层网络探针
            TARGET_URL="https://connectivitycheck.gstatic.com/generate_204"
            ACTION_LOG="NetTest"
        fi
    elif [ "$UA_PLATFORM" == "ios" ] || [ "$UA_PLATFORM" == "macos" ]; then
        if [ $ACTION_DICE -lt 30 ]; then
            TARGET_URL="https://www.google.com/search?q=${ENCODED_KEY}&${LANG_PARAMS}"
            ACTION_LOG="Search "
        elif [ $ACTION_DICE -lt 65 ]; then
            TARGET_URL="https://news.google.com/home?${LANG_PARAMS}"
            ACTION_LOG="News   "
        elif [ $ACTION_DICE -lt 90 ]; then
            TARGET_URL="https://www.google.com/maps/search/${ENCODED_KEY}/@${ACTION_LAT},${ACTION_LON},17z?${LANG_PARAMS}"
            ACTION_LOG="Maps   "
        else
            # Apple 专属的 Captive Portal 探针，杜绝跨平台穿帮
            TARGET_URL="https://captive.apple.com/hotspot-detect.html"
            ACTION_LOG="NetTest"
        fi
    else
        # Windows / Linux 专属行为矩阵 (无移动端探针，加入隐私/支持页漫游)
        if [ $ACTION_DICE -lt 20 ]; then
            TARGET_URL="https://www.google.com/search?q=${ENCODED_KEY}&${LANG_PARAMS}"
            ACTION_LOG="Search "
        elif [ $ACTION_DICE -lt 60 ]; then
            TARGET_URL="https://news.google.com/home?${LANG_PARAMS}"
            ACTION_LOG="News   "
        elif [ $ACTION_DICE -lt 80 ]; then
            # 引入桌面端低危生态池漫游
            LOW_RISK_ECO=("https://about.google/" "https://safety.google/" "https://support.google.com/?hl=${LANG_ACCEPT%%,*}")
            TARGET_URL="${LOW_RISK_ECO[$((RANDOM % ${#LOW_RISK_ECO[@]}))]}"
            ACTION_LOG="EcoRoam"
        else
            TARGET_URL="https://www.google.com/maps/search/${ENCODED_KEY}/@${ACTION_LAT},${ACTION_LON},17z?${LANG_PARAMS}"
            ACTION_LOG="Maps   "
        fi
    fi
    
    # [v4.1.5 修复] 匹配当前业务对应的 Referer 来源
    CTX_REF=""
    case "$ACTION_LOG" in
        "Search "*) CTX_REF="$REF_SEARCH" ;;
        "News   "*) CTX_REF="$REF_NEWS" ;;
        "Maps   "*) CTX_REF="$REF_MAPS" ;;
        "EcoRoam"*) CTX_REF="$REF_ECO" ;;
    esac

    # [v4.1.3 & v4.1.5 修复] 统一执行 curl，70% 概率携带同业务域 Referer
    if [ -n "$CTX_REF" ] && [ $((RANDOM % 100)) -lt 70 ]; then
        CODE=$(curl "${CURL_BIND_ARGS[@]}" "$DYNAMIC_IP_PREF" -m 15 -s -L -o /dev/null -w "%{http_code}" \
             -b "$COOKIE_FILE" -c "$COOKIE_FILE" -A "$SESSION_UA" -H "Referer: $CTX_REF" "$TARGET_URL")
    else
        CODE=$(curl "${CURL_BIND_ARGS[@]}" "$DYNAMIC_IP_PREF" -m 15 -s -L -o /dev/null -w "%{http_code}" \
             -b "$COOKIE_FILE" -c "$COOKIE_FILE" -A "$SESSION_UA" "$TARGET_URL")
    fi
    CURL_EXIT=$?
    
    # 错误码精准映射（不破坏原有的 SCORE 送中判定，只让动作日志更清晰）
    if [ $CURL_EXIT -ne 0 ]; then
        case $CURL_EXIT in
            6)  CODE="ERR_DNS" ;;
            7)  CODE="ERR_CONN" ;;
            28) CODE="ERR_TIMEOUT" ;;
            35) CODE="ERR_TLS" ;;
            56) CODE="ERR_RESET" ;;
            *)  CODE="ERR_${CURL_EXIT}" ;;
        esac
        log "$MODULE_NAME" "WARN " "动作[$i/$TOTAL_ACTIONS]异常 | 底层错误: $CODE | 抖动坐标: $ACTION_LAT, $ACTION_LON"
        
        # [v4.1.5] 请求失败，清空当前业务链的 Referer
        case "$ACTION_LOG" in
            "Search "*) REF_SEARCH="" ;;
            "News   "*) REF_NEWS="" ;;
            "Maps   "*) REF_MAPS="" ;;
            "EcoRoam"*) REF_ECO="" ;;
        esac
    else
        log "$MODULE_NAME" "EXEC " "动作[$i/$TOTAL_ACTIONS]完成 | HTTP状态: $CODE | 抖动坐标: $ACTION_LAT, $ACTION_LON"
        
        # [v4.1.5] 请求成功，记录当前 URL 作为同业务下一次跳转的 Referer (2xx 或 3xx 视为有效)
        if [[ "$CODE" =~ ^[23] ]]; then
            case "$ACTION_LOG" in
                "Search "*) REF_SEARCH="$TARGET_URL" ;;
                "News   "*) REF_NEWS="$TARGET_URL" ;;
                "Maps   "*) REF_MAPS="$TARGET_URL" ;;
                "EcoRoam"*) REF_ECO="$TARGET_URL" ;;
            esac
        fi
    fi
    
    # 【核心升级】行为拉伸：每次动作后强制休眠 90 - 120 秒
    # 结合动作总数，总耗时将稳定在 10 分钟 到 20 分钟之间
    if [ $i -lt $TOTAL_ACTIONS ]; then
        # 【时间收敛修复】休眠控制在 45-75 秒，防止跨周期重叠导致进程被强杀
        SLEEP_TIME=$((45 + RANDOM % 31))
        log "$MODULE_NAME" "WAIT " "阅读当前页面内容，模拟停留 $SLEEP_TIME 秒..."
        sleep "$SLEEP_TIME"
    fi
done

# -----------------------------------------------------------
# [态势感知] 三核探测雷达 (跳转 / Premium / Music)
# -----------------------------------------------------------
log "$MODULE_NAME" "INFO " "启动三核交叉验证 (URL跳转 + YT Premium + YT Music) 穿透获取 GeoIP..."

# 核心 1: 传统 URL 跳转探测 (请求 www 才能触发准确跳转)
# [v4.1.2] 追加持久化 Cookie
JUMP_HDR=$(curl "${CURL_BIND_ARGS[@]}" "$DYNAMIC_IP_PREF" -m 10 -sI -b "$COOKIE_FILE" -c "$COOKIE_FILE" "http://www.google.com/")
JUMP_LOC=$(echo "$JUMP_HDR" | grep -i "^location:" | tr -d '\r\n')
JUMP_GL=""

if [ -z "$JUMP_LOC" ]; then
    JUMP_GL="US"
elif [[ "$JUMP_LOC" == *".google.cn"* ]] || [[ "$JUMP_LOC" == *"gl=CN"* ]]; then
    JUMP_GL="CN"
elif [[ "$JUMP_LOC" == *"gl="* ]]; then
    JUMP_GL=$(echo "$JUMP_LOC" | grep -o 'gl=[A-Za-z]\{2\}' | head -n 1 | cut -d'=' -f2 | tr 'a-z' 'A-Z')
else
    JUMP_DOMAIN=$(echo "$JUMP_LOC" | grep -o 'google\.[a-z\.]*' | head -n 1 | sed 's/google\.//')
    case "$JUMP_DOMAIN" in
        "com") JUMP_GL="US" ;;
        "com.hk") JUMP_GL="HK" ;;
        "com.tw") JUMP_GL="TW" ;;
        "co.jp") JUMP_GL="JP" ;;
        "co.uk") JUMP_GL="GB" ;;
        "co.kr") JUMP_GL="KR" ;;
        "co.in") JUMP_GL="IN" ;;
        "co.id") JUMP_GL="ID" ;;
        "co.th") JUMP_GL="TH" ;;
        "com.sg") JUMP_GL="SG" ;;
        "com.my") JUMP_GL="MY" ;;
        "com.au") JUMP_GL="AU" ;;
        "com.br") JUMP_GL="BR" ;;
        "com.mx") JUMP_GL="MX" ;;
        "com.ar") JUMP_GL="AR" ;;
        "co.za") JUMP_GL="ZA" ;;
        "cn") JUMP_GL="CN" ;;
        "") JUMP_GL="" ;;
        *) 
            LAST_EXT=$(echo "$JUMP_DOMAIN" | awk -F'.' '{print $NF}' | tr 'a-z' 'A-Z')
            if [ ${#LAST_EXT} -eq 2 ]; then
                JUMP_GL="$LAST_EXT"
            else
                JUMP_GL="US"
            fi
            ;;
    esac
fi

# ==========================================================
# [v4.2.3 修复 - PR #82 剥离探测身份]
# 抛弃模拟人类漫游时使用的混杂老旧 UA 及污染 Cookie，
# 强制使用绝对干净且现代的 Windows Chrome UA 发起探针裸请求，
# 确保边缘服务器必定下发完整的 SPA 框架页面，防止 INNERTUBE 提取报错。
# ==========================================================
PROBE_UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

extract_yt_gl() {
    grep -Eo '"(contentRegion|countryCode|INNERTUBE_CONTEXT_GL|GL)":"[A-Za-z]{2}"' | head -n 1 | cut -d'"' -f4 | tr 'a-z' 'A-Z'
}

# 核心 2: YouTube Premium 区域锁嗅探
YT_PR_GL=""
YT_PR_HTML=$(curl "${CURL_BIND_ARGS[@]}" "$DYNAMIC_IP_PREF" -m 12 -s -L -A "$PROBE_UA" "https://www.youtube.com/premium")
if [[ "$YT_PR_HTML" == *"www.google.cn"* ]]; then
    YT_PR_GL="CN"
else
    YT_PR_GL=$(printf '%s' "$YT_PR_HTML" | extract_yt_gl)
fi

# 核心 3: YouTube Music 区域锁嗅探
YT_MU_GL=""
YT_MU_HTML=$(curl "${CURL_BIND_ARGS[@]}" "$DYNAMIC_IP_PREF" -m 12 -s -L -A "$PROBE_UA" "https://music.youtube.com/")
if [[ "$YT_MU_HTML" == *"www.google.cn"* ]]; then
    YT_MU_GL="CN"
else
    YT_MU_GL=$(printf '%s' "$YT_MU_HTML" | extract_yt_gl)
fi

# [坐标规整] 兼容横杠分割体系，并修正英区缩写
TARGET_CC="${REGION_CODE%%-*}"
[ "$TARGET_CC" == "UK" ] && TARGET_CC="GB"

# -----------------------------------------------------------
# [终极审判] 异常过滤与一致性裁决机制
# -----------------------------------------------------------
IS_CN=0
VALID_PROBES=0

for val in "$JUMP_GL" "$YT_PR_GL" "$YT_MU_GL"; do
    if [ -n "$val" ]; then
        ((VALID_PROBES++))
        [ "$val" == "CN" ] && IS_CN=1
    fi
done

if [ $VALID_PROBES -eq 0 ]; then
    STATUS="🚨 探针失效 (三核全部熔断，可能遭严重风控拦截)"
elif [ $IS_CN -eq 1 ]; then
    STATUS="❌ 严重高危！三核雷达判定 IP 已被中国大陆锁定 (送中)！"
else
    # [权重仲裁] 以流媒体核心解锁状态为主导，允许基础网段跨国漂移
    YT_MATCH=0
    [ "$YT_PR_GL" == "$TARGET_CC" ] && YT_MATCH=1
    [ "$YT_MU_GL" == "$TARGET_CC" ] && YT_MATCH=1

    if [ $YT_MATCH -eq 1 ]; then
        if [ -n "$JUMP_GL" ] && [ "$JUMP_GL" != "$TARGET_CC" ]; then
            STATUS="✅ 目标区域达成 (YT主导成功, Jump副雷达漂移至 ${JUMP_GL}) | Prem: ${YT_PR_GL:-无} | Music: ${YT_MU_GL:-无}"
        else
            STATUS="✅ 目标区域达成 (Jump: ${JUMP_GL:-无} | Prem: ${YT_PR_GL:-无} | Music: ${YT_MU_GL:-无})"
        fi
    else
        STATUS="⚠️ 区域发生漂移！目标 $TARGET_CC，实际 (Jump: ${JUMP_GL:-无} | Prem: ${YT_PR_GL:-无} | Music: ${YT_MU_GL:-无})"
    fi
fi

log "$MODULE_NAME" "SCORE" "自检结论: $STATUS"
log "$MODULE_NAME" "END  " "========== 会话结束，释放进程 =========="