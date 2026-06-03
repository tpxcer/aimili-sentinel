// IP-Sentinel Glasshouse Telemetry (全透明装机量统计中枢)
// 部署环境: Cloudflare Workers + KV
// 隐私声明: 绝对不采集、不存储用户的 IP 地址、Header、Token 及任何系统特征参数。仅做纯粹的原子累加。

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    // 全局跨域头，确保 GitHub README 的 Shields.io 徽章能正常读取
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET",
    };

    // 核心原子操作：无情的 +1 机器
    async function incrementCounter(key) {
      let count = await env.SENTINEL_KV.get(key);
      count = count ? parseInt(count) + 1 : 1;
      await env.SENTINEL_KV.put(key, count.toString());
      return count;
    }

    async function getCounter(key) {
      let count = await env.SENTINEL_KV.get(key);
      return count ? parseInt(count) : 0;
    }

    try {
      // 1. Agent (哨兵) 部署触发接口
      if (path === '/ping/agent') {
        const count = await incrementCounter('agent_count');
        return new Response(count.toString(), { headers: corsHeaders });
      }
      
      // 2. Master (指挥部) 部署触发接口
      if (path === '/ping/master') {
        const count = await incrementCounter('master_count');
        return new Response(count.toString(), { headers: corsHeaders });
      }

      // 3. GitHub README Agent 徽章接口 (输出给 Shields.io)
      if (path === '/stats/agent') {
        const count = await getCounter('agent_count');
        const shield = {
          schemaVersion: 1,
          label: "Agent Nodes",
          message: count.toString(),
          color: "blue"
        };
        return new Response(JSON.stringify(shield), { 
          headers: { ...corsHeaders, "Content-Type": "application/json" } 
        });
      }

      // 4. GitHub README Master 徽章接口 (输出给 Shields.io)
      if (path === '/stats/master') {
        const count = await getCounter('master_count');
        const shield = {
          schemaVersion: 1,
          label: "Master Commands",
          message: count.toString(),
          color: "orange"
        };
        return new Response(JSON.stringify(shield), { 
          headers: { ...corsHeaders, "Content-Type": "application/json" } 
        });
      }

      return new Response("IP-Sentinel Glasshouse Telemetry API (No IP Logged, 100% Transparent)", { status: 200 });
    } catch (err) {
      return new Response("Error", { status: 500 });
    }
  }
};
