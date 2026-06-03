import urllib.request
import xml.etree.ElementTree as ET
import os
import json
import re
import time
import random

# ================== [路径防弹装甲] ==================
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)

MAP_JSON_PATH = os.path.join(PROJECT_ROOT, "data", "map.json")
DATA_DIR = os.path.join(PROJECT_ROOT, "data", "keywords")
# ====================================================

GEO_FIX = {'UK': 'GB'}
FALLBACK_MAP = {'LA': 'US', 'MN': 'US', 'MO': 'HK'}

USER_AGENTS = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36'
]

def get_active_regions():
    try:
        with open(MAP_JSON_PATH, 'r', encoding='utf-8') as f:
            data = json.load(f)
            regions = []
            for continent in data.get('continents', []):
                for country in continent.get('countries', []):
                    if 'id' in country:
                        regions.append(country['id'])
            return regions
    except Exception as e:
        print(f"❌ [读取地图失败]: {e}")
        return []

def fetch_trends(region_code):
    geo = GEO_FIX.get(region_code, region_code)
    actual_geo = FALLBACK_MAP.get(geo, geo)
    url = f"https://trends.google.com/trending/rss?geo={actual_geo}"
    headers = {'User-Agent': random.choice(USER_AGENTS)}
    
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=10) as response:
            xml_data = response.read()
            root = ET.fromstring(xml_data)
            fallback_msg = f" (兜底降级至 {actual_geo})" if actual_geo != geo else ""
            words = [re.sub(r'[\n\r\t]', ' ', item.find('title').text).strip() 
                    for item in root.findall('./channel/item') 
                    if item.find('title') is not None]
            return words, fallback_msg
    except Exception as e:
        print(f"⚠️ {region_code} 抓取异常: {e}")
        return [], ""

def update_file(region, new_words, fallback_msg=""):
    """滑动窗口更新，严格保留最新 100 条最热记录"""
    os.makedirs(DATA_DIR, exist_ok=True)
    file_path = os.path.join(DATA_DIR, f"kw_{region}.txt")
    old_words = []
    if os.path.exists(file_path):
        with open(file_path, 'r', encoding='utf-8') as f:
            old_words = [l.strip() for l in f if l.strip()]
    
    combined = new_words + [w for w in old_words if w not in new_words]
    # 【业务收敛】切片收紧至 100 条
    final_list = combined[:100]
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(final_list) + '\n')
    print(f"✅ [同步完成] {region}: 注入 {len(new_words)} 条新热点，维持总数 {len(final_list)} 条{fallback_msg}")

if __name__ == '__main__':
    regions = get_active_regions()
    if not regions:
        print("🛑 未发现活跃战区，请检查 map.json")
        exit(1)
    
    print("========== 启动 IP-Sentinel 动态热词抓取引擎 ==========")
    for r in regions:
        print(f"📡 正在拉取 {r} 战区情报...")
        words, fallback_msg = fetch_trends(r)
        if words:
            update_file(r, words, fallback_msg)
        time.sleep(random.uniform(1.5, 3.5))
    print("========== 热词抓取引擎执行完毕 ==========")