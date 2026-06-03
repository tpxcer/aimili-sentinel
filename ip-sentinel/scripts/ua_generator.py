import random
import os

# ==========================================================
# IP-Sentinel 终极动态指纹工厂 (V5.1.1 - 破除死循环抢修版)
# 战术核心:
# 1. 放弃 set 去重，允许重复特征存在 (真实世界本就如此)
# 2. 彻底解决组合基数过小导致的 Infinite Loop 卡死问题
# ==========================================================

TOTAL_POOL = 4000

def weighted_choice(weighted_items):
    items = []
    for value, weight in weighted_items:
        items.extend([value] * weight)
    return random.choice(items)

# ----------------------------------------------------------
# 核心组件库
# ----------------------------------------------------------
FIREFOX_ESR_VERSIONS = [
    ("115.0", 50), 
    ("128.0", 50), 
]

OLD_CHROME_VERSIONS = [
    ("109", 40), 
    ("114", 30),
    ("120", 30),
]

def generate_ff_ver():
    return weighted_choice(FIREFOX_ESR_VERSIONS)

def generate_old_chrome():
    major = weighted_choice(OLD_CHROME_VERSIONS)
    build = random.randint(5000, 6099)
    patch = random.randint(40, 150)
    return f"{major}.0.{build}.{patch}"

# ----------------------------------------------------------
# 1. Linux Firefox ESR (35% -> 1400条)
# ----------------------------------------------------------
def generate_linux_firefox(count=1400):
    uas = []
    for _ in range(count):
        ff_ver = generate_ff_ver()
        distro = random.choice(["X11; Linux x86_64", "X11; Ubuntu; Linux x86_64", "X11; Fedora; Linux x86_64"])
        uas.append(f"Mozilla/5.0 ({distro}; rv:{ff_ver}) Gecko/20100101 Firefox/{ff_ver}")
    return uas

# ----------------------------------------------------------
# 2. Windows Firefox ESR (25% -> 1000条)
# ----------------------------------------------------------
def generate_windows_firefox(count=1000):
    uas = []
    for _ in range(count):
        ff_ver = generate_ff_ver()
        os_ver = random.choices(["Windows NT 10.0", "Windows NT 6.1"], weights=[80, 20])[0]
        uas.append(f"Mozilla/5.0 ({os_ver}; Win64; x64; rv:{ff_ver}) Gecko/20100101 Firefox/{ff_ver}")
    return uas

# ----------------------------------------------------------
# 3. Android Firefox (15% -> 600条)
# ----------------------------------------------------------
def generate_android_firefox(count=600):
    uas = []
    for _ in range(count):
        android_ver = random.choice([11, 12, 13, 14])
        ff_ver = generate_ff_ver()
        uas.append(f"Mozilla/5.0 (Android {android_ver}; Mobile; rv:{ff_ver}) Gecko/{ff_ver} Firefox/{ff_ver}")
    return uas

# ----------------------------------------------------------
# 4. 降现代化 Chromium 池 (15% -> 600条)
# ----------------------------------------------------------
def generate_old_chromium(count=600):
    uas = []
    mid_end_models = [
        "SM-A546B", "SM-A346B", "SM-M146B", "moto g84 5G", "moto g play", 
        "2312DRA50G", "V2318", "CPH2581"
    ]
    for _ in range(count):
        platform = random.choices(["windows", "android"], weights=[40, 60])[0]
        chrome_ver = generate_old_chrome()
        
        if platform == "windows":
            os_ver = random.choices(["Windows NT 10.0", "Windows NT 6.1"], weights=[70, 30])[0]
            uas.append(f"Mozilla/5.0 ({os_ver}; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/{chrome_ver} Safari/537.36")
        else:
            android_ver = random.choice([10, 11, 12, 13])
            model = random.choice(mid_end_models)
            uas.append(f"Mozilla/5.0 (Linux; Android {android_ver}; {model}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/{chrome_ver} Mobile Safari/537.36")
    return uas

# ----------------------------------------------------------
# 5. 少量生态噪声 Safari (10% -> 400条)
# ----------------------------------------------------------
def generate_safari_noise(count=400):
    uas = []
    for _ in range(count):
        device = random.choices(["mac", "iphone"], weights=[40, 60])[0]
        safari_webkit = random.choice(["605.1.15", "615.1.26"])
        
        if device == "mac":
            mac_major = random.choice([12, 13])
            mac_minor = random.randint(0, 6)
            uas.append(f"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_{mac_major}_{mac_minor}) AppleWebKit/{safari_webkit} (KHTML, like Gecko) Version/15.6 Safari/{safari_webkit}")
        else:
            ios_major = random.choice([15, 16])
            ios_minor = random.randint(0, 5)
            uas.append(f"Mozilla/5.0 (iPhone; CPU iPhone OS {ios_major}_{ios_minor} like Mac OS X) AppleWebKit/{safari_webkit} (KHTML, like Gecko) Version/{ios_major}.0 Mobile/15E148 Safari/{safari_webkit}")
    return uas

# ----------------------------------------------------------
# 主程序
# ----------------------------------------------------------
if __name__ == "__main__":
    os.makedirs("data", exist_ok=True)
    pool = []

    pool.extend(generate_linux_firefox(1400))    
    pool.extend(generate_windows_firefox(1000))  
    pool.extend(generate_android_firefox(600))   
    pool.extend(generate_old_chromium(600))      
    pool.extend(generate_safari_noise(400))      

    random.shuffle(pool)

    final_pool = pool[:TOTAL_POOL]

    output_file = "data/user_agents.txt"
    with open(output_file, "w", encoding="utf-8") as f:
        for ua in final_pool:
            f.write(ua + "\n")

    print(f"✅ 成功生成 {len(final_pool)} 条大智若愚架构指纹库 (V5.1.1 破除卡死版)")