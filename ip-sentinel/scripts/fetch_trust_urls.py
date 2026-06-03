import urllib.request
import xml.etree.ElementTree as ET
import os
import json
import random
import re

# ====================================================
# 脚本功能: 5+25 混合流量注入矩阵 (自适应解耦版)
# 核心指标: 5条基石 + 25条活体新闻 = 30条确保双栈机型完全可达的白名单
# ====================================================

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
REGIONS_DIR = os.path.join(PROJECT_ROOT, "data", "regions")

# ====================================================
# 2025 年高保真多平台 UA 轮换池 (防风控装甲)
# 包含 Windows, macOS, iOS, Android 的最新骨干指纹
# ====================================================
USER_AGENTS = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36 Edg/133.0.0.0',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:135.0) Gecko/20100101 Firefox/135.0',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/618.1.15 (KHTML, like Gecko) Version/18.3 Safari/618.1.15',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_3_1 like Mac OS X) AppleWebKit/618.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1',
    'Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Mobile Safari/537.36'
]

# ====================================================
# 全球骨干新闻 RSS 监听矩阵 (双栈强穿透版)
# 全面采用 Google News 本土化入口，确保提取的链接支持 IPv4+IPv6
# ====================================================
RSS_FEEDS = {
    "US": ["https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en"],
    "UK": ["https://news.google.com/rss?hl=en-GB&gl=GB&ceid=GB:en"],
    "AU": ["https://news.google.com/rss?hl=en-AU&gl=AU&ceid=AU:en"],
    "CA": ["https://news.google.com/rss?hl=en-CA&gl=CA&ceid=CA:en"],
    "DE": ["https://news.google.com/rss?hl=de&gl=DE&ceid=DE:de"],
    "FR": ["https://news.google.com/rss?hl=fr&gl=FR&ceid=FR:fr"],
    "ES": ["https://news.google.com/rss?hl=es-419&gl=US&ceid=US:es_419"],
    "JP": ["https://news.google.com/rss?hl=ja&gl=JP&ceid=JP:ja"],
    "HK": ["https://news.google.com/rss?hl=zh-HK&gl=HK&ceid=HK:zh-Hant"],
    "MO": ["https://news.google.com/rss?hl=zh-HK&gl=HK&ceid=HK:zh-Hant"],
    "TW": ["https://news.google.com/rss?hl=zh-TW&gl=TW&ceid=TW:zh-Hant"],
    "KR": ["https://news.google.com/rss?hl=ko&gl=KR&ceid=KR:ko"],
    "SG": ["https://news.google.com/rss?hl=en-SG&gl=SG&ceid=SG:en"],
    "NL": ["https://news.google.com/rss?hl=nl&gl=NL&ceid=NL:nl"],
    "VN": ["https://news.google.com/rss?hl=vi&gl=VN&ceid=VN:vi"],
    "MY": ["https://news.google.com/rss?hl=en-MY&gl=MY&ceid=MY:en"],
    "NG": ["https://news.google.com/rss?hl=en-NG&gl=NG&ceid=NG:en"],
    "TR": ["https://news.google.com/rss?hl=tr&gl=TR&ceid=TR:tr"],
    "PH": ["https://news.google.com/rss?hl=en-PH&gl=PH"],
    "TH": ["https://news.google.com/rss?hl=th&gl=TH&ceid=TH:th"],
    "ID": ["https://news.google.com/rss?hl=id&gl=ID&ceid=ID:id"],
    "IN": ["https://news.google.com/rss?hl=en-IN&gl=IN&ceid=IN:en"],
    "AE": ["https://news.google.com/rss?hl=en-AE&gl=AE"],
    "SA": ["https://news.google.com/rss?hl=ar-SA&gl=SA"],
    "BD": ["https://news.google.com/rss?hl=en-BD&gl=BD"],
    "NP": ["https://news.google.com/rss?hl=en-NP&gl=NP"],
    "KH": ["https://news.google.com/rss?hl=en-KH&gl=KH"],
    "MM": ["https://news.google.com/rss?hl=en-MM&gl=MM"],
    "LA": ["https://news.google.com/rss?hl=en-LA&gl=LA"],
    "MN": ["https://news.google.com/rss?hl=en-MN&gl=MN"]
}

def is_dual_stack_safe(url):
    """网络可达性过滤: 阻断任何不支持双栈(IPv4+IPv6)的动态新闻域名"""
    DUAL_STACK_SAFE_DOMAINS = [
        "google.com", "wikipedia.org", "apple.com", "microsoft.com", 
        "wikimedia.org", "blogspot.com", "yahoo.com"
    ]
    return any(domain in url for domain in DUAL_STACK_SAFE_DOMAINS)

def fetch_rss_links(lang_params, region_name, max_items=25):
    """根据 JSON 提供的语言参数，动态拼接对应国家的 Google 新闻源"""
    # [核心解耦]：直接使用 json 文件中的 lang_params，彻底淘汰 RSS_FEEDS 字典
    url = f"https://news.google.com/rss?{lang_params}"
    links = []
    
    try:
        dynamic_headers = {'User-Agent': random.choice(USER_AGENTS)}
        req = urllib.request.Request(url, headers=dynamic_headers)
        with urllib.request.urlopen(req, timeout=10) as response:
            xml_data = response.read()
            root = ET.fromstring(xml_data)
            for item in root.findall('.//item'):
                link = item.find('link')
                if link is not None and link.text:
                    clean_link = link.text.strip()
                    # 仅对动态获取的不可控新闻链接应用双栈过滤
                    if clean_link.startswith('http') and is_dual_stack_safe(clean_link):
                        links.append(clean_link)
    except Exception as e:
        print(f"⚠️ [{region_name}] 本土 RSS 抓取异常 ({url}): {e}")
        
    unique_links = list(set(links))
    random.shuffle(unique_links)
    return unique_links[:max_items]

def process_json_file(file_path):
    """解析单节点配置并执行流量注入"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            
        trust_mod = data.get("trust_module", {})
        google_mod = data.get("google_module", {})
        region_name = data.get("region_name", "Unknown")
        
        if not trust_mod or not google_mod:
            return
            
        # 1. 提取语言参数 (如 hl=en-AE&gl=AE)
        lang_params = google_mod.get("lang_params", "hl=en-US&gl=US")
        
        # 2. 智能提取语种前缀，用于维基百科的本土化 (如 hl=ja 提取出 ja)
        hl_match = re.search(r'hl=([a-zA-Z]+)', lang_params)
        # 如果带有地区后缀(如 zh-TW, en-GB)，则只取前面代表语种的字母
        lang_prefix = hl_match.group(1).split('-')[0].lower() if hl_match else 'en'
        
        # 3. 基石处理：【修复点】直接提取静态基石，不做双栈硬编码过滤，保护本地化域名！
        static_urls = trust_mod.get("static_urls", [])
        
        if len(static_urls) < 5:
            # 基础数据残缺时，采用本土化的 Wikipedia 域名垫底
            static_urls += [f"https://{lang_prefix}.wikipedia.org/wiki/Special:Random", "https://www.apple.com/", "https://www.microsoft.com/"]
        random.shuffle(static_urls)
        final_static = list(set(static_urls))[:5]
        
        # 4. 将本地语言参数传给 RSS 爬虫，拉取活体新闻
        final_news = fetch_rss_links(lang_params, region_name, max_items=25)
        
        combined_urls = list(set(final_static + final_news))
        
        # 5. 采用完全本土化的维基百科执行最终充能
        while len(combined_urls) < 30:
            combined_urls.append(f"https://{lang_prefix}.wikipedia.org/wiki/Special:Random?r={random.randint(1,100000)}")
            combined_urls = list(set(combined_urls))
            
        final_white_list = combined_urls[:30]
        random.shuffle(final_white_list)
        
        trust_mod["white_urls"] = final_white_list
        data["trust_module"] = trust_mod
        
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            
        print(f"✅ [信用融合] {os.path.basename(file_path)} (语系: {lang_prefix}): 固化基石 {len(final_static)} 条 + 活体新闻 {len(final_news)} 条 = 统合满编 {len(final_white_list)} 条")
        
    except Exception as e:
        print(f"❌ [处理失败] {file_path}: {e}")

if __name__ == '__main__':
    print("========== 启动 IP-Sentinel 活体新闻流融合引擎 (自适应架构版) ==========")
    for root_dir, _, files in os.walk(REGIONS_DIR):
        for file in files:
            if file.endswith(".json"):
                file_path = os.path.join(root_dir, file)
                process_json_file(file_path)
    print("========== 融合引擎执行完毕 ==========")