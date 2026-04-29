/**
 * 系統聯通圖頁 — vis-network 控制邏輯 (Stage 1: 骨架 + 手動 CRUD + 靜態渲染)
 *
 * 後續階段:
 *  - Stage 2: 故障模擬動畫 (depSimulateFailure 完整實作)
 *  - Stage 3: 採集按鈕觸發 (collect button)
 */
(function () {
  "use strict";

  let _network = null;
  let _nodes = null;
  let _edges = null;
  let _selectedId = null;
  let _allNodesCache = [];

  // ----- 初始化 -----
  document.addEventListener("DOMContentLoaded", function () {
    depReload();
  });

  // ----- 主要載入 -----
  window.depReload = function () {
    const tier = document.getElementById("dep-tier-filter").value;
    const depth = document.getElementById("dep-depth").value;
    const viewEl = document.getElementById("dep-view");
    const view = viewEl ? viewEl.value : "system";
    const params = new URLSearchParams({ depth: depth, limit: "300", view: view });
    if (_selectedId) params.set("center", _selectedId);
    setMeta("載入中...");
    fetch("/api/dependencies/topology?" + params.toString(), { credentials: "include" })
      .then(function (r) { return r.json(); })
      .then(function (res) {
        if (!res.success) {
          setMeta("⚠️ 載入失敗: " + (res.error || ""));
          return;
        }
        let data = res.data;
        if (tier) {
          const allowed = new Set(data.nodes.filter(function (n) { return (n.tier || "C") === tier; }).map(function (n) { return n.system_id; }));
          data.nodes = data.nodes.filter(function (n) { return allowed.has(n.system_id); });
          data.edges = data.edges.filter(function (e) { return allowed.has(e.from) && allowed.has(e.to); });
        }
        renderTopology(data);
      })
      .catch(function (err) { setMeta("⚠️ 網路錯誤: " + err.message); });
  };

  function setMeta(text) {
    const el = document.getElementById("dep-meta");
    if (el) el.textContent = text;
  }

  // ----- 渲染 -----
  function renderTopology(data) {
    _allNodesCache = data.nodes || [];
    const view = (data.meta && data.meta.view) || "system";
    const visNodes = (data.nodes || []).map(function(n){ return toVisNode(n, view); });
    const visEdges = (data.edges || []).map(toVisEdge);

    _nodes = new vis.DataSet(visNodes);
    _edges = new vis.DataSet(visEdges);

    const container = document.getElementById("dep-canvas");
    // 0 edges 時 hierarchical+sortMethod=directed 會把所有 nodes 擠同一 level
    // 看起來像「畫不出來」(實際上是疊在一起) — 自動切 free layout + physics 散開
    const hasEdges = visEdges.length > 0;
    const options = {
      autoResize: true,
      nodes: {
        shape: "dot",
        size: 22,
        font: { size: 13, face: "Inter, system-ui", color: "#222" },
        borderWidth: 2,
      },
      edges: {
        arrows: { to: { enabled: true, scaleFactor: 0.6 } },
        smooth: false,
        font: { size: 10, align: "middle", color: "#666", strokeWidth: 0 },
        color: { color: "#888", highlight: "#1a73e8", hover: "#1a73e8" },
      },
      layout: hasEdges ? {
        hierarchical: {
          enabled: true,
          direction: "LR",
          sortMethod: "directed",
          levelSeparation: 220,
          nodeSpacing: 130,
          treeSpacing: 200,
          shakeTowards: "leaves",
        },
      } : { hierarchical: { enabled: false }, randomSeed: 42 },
      physics: hasEdges ? false : {
        enabled: true,
        solver: "repulsion",
        repulsion: { nodeDistance: 180, springLength: 200 },
        stabilization: { iterations: 150, fit: true },
      },
      interaction: { hover: true, navigationButtons: false, keyboard: true, dragNodes: true },
    };

    if (_network) _network.destroy();
    _network = new vis.Network(container, { nodes: _nodes, edges: _edges }, options);
    window._dep_network = _network;
    console.log("[dep] vis.Network init", { nodes: visNodes.length, edges: visEdges.length, w: container.offsetWidth, h: container.offsetHeight });

    // 物理引擎穩定後關掉 (避免持續吃 CPU)
    _network.once("stabilizationIterationsDone", function () {
      console.log("[dep] stabilization done, disable physics");
      _network.setOptions({ physics: { enabled: false } });
      try { _network.fit({ animation: false }); } catch (e) {}
    });

    // 強制 redraw 修 grid 初次量測 0 寬高 bug
    setTimeout(function () {
      try {
        _network.redraw();
        _network.fit({ animation: false });
        var canvas = container.querySelector("canvas");
        console.log("[dep] 200ms check, canvas:", canvas ? canvas.width + "x" + canvas.height : "MISSING");
      } catch (e) { console.error("[dep] redraw err", e); }
    }, 200);
    setTimeout(function () { try { _network.redraw(); _network.fit({ animation: true }); } catch (e) {} }, 1500);
    _network.on("selectNode", function (params) { onNodeSelect(params.nodes[0]); });
    _network.on("doubleClick", function (params) {
      if (params.nodes.length) { _selectedId = params.nodes[0]; depReload(); }
    });

    const meta = data.meta || {};
    const baseMsg = "節點數 " + (meta.node_count || visNodes.length) + " / 邊數 " + (meta.edge_count || visEdges.length) +
      (meta.truncated ? " (已截斷至 limit)" : "") +
      (meta.center ? " — 中心: " + meta.center : "");
    if (visEdges.length === 0 && visNodes.length > 0) {
      // 0 邊 → 提示去採集 (常見於剛部署或 dependency_relations 是空的)
      setMetaHTML(baseMsg + ' <span style="color:#e67e22;margin-left:12px;">⚠️ 還沒採集任何邊資料</span> ' +
        '<a href="/admin#dependencies" class="btn btn-sm" style="margin-left:6px;">前往採集 →</a>');
    } else {
      setMeta(baseMsg);
    }
  }

  function setMetaHTML(html) {
    const el = document.getElementById("dep-meta");
    if (el) el.innerHTML = html;
  }

  // 採集觸發 — 從 fullscreen.html inline 搬過來共用 (v3.17.10.3+)
  window.depTriggerCollect = async function () {
    const btn = document.getElementById("dep-collect-btn");
    if (!btn) return;
    btn.disabled = true;
    const orig = btn.innerHTML;
    btn.innerHTML = "⏳ 採集中...";
    try {
      const r = await fetch("/api/dependencies/collect/trigger", { method: "POST", credentials: "include" });
      if (r.status === 401) { alert("未登入或 session 過期\n請重新登入後再試"); btn.disabled = false; btn.innerHTML = orig; return; }
      if (r.status === 403) { alert("權限不足 — 需 admin/superadmin 才能觸發採集"); btn.disabled = false; btn.innerHTML = orig; return; }
      const res = await r.json();
      if (!res.success) { alert("採集失敗: " + (res.error || "")); btn.disabled = false; btn.innerHTML = orig; return; }
      const runId = res.data.run_id;
      let polls = 0;
      const timer = setInterval(async function () {
        polls++;
        const s = await fetch("/api/dependencies/collect/status/" + runId, { credentials: "include" }).then(x => x.json());
        if (s.success && s.data && (s.data.status === "success" || s.data.status === "failed")) {
          clearInterval(timer);
          btn.disabled = false; btn.innerHTML = orig;
          if (s.data.status === "success") {
            const m = s.data;
            alert("✓ 採集完成\n新增邊: " + (m.edges_added || 0) + " / 更新: " + (m.edges_updated || 0) +
              (m.new_unknowns && m.new_unknowns.length ? "\n新發現未知 IP: " + m.new_unknowns.join(", ") : ""));
            window.depReload && window.depReload();
          } else {
            alert("✗ 採集失敗: " + (s.data.error || ""));
          }
        } else if (polls > 60) {
          clearInterval(timer);
          btn.disabled = false; btn.innerHTML = orig;
          alert("採集超過 5 分鐘未完成 — 按「📊 狀態」續看或 ssh 到 host 看 logs/dep_collect_*.log");
        }
      }, 5000);
    } catch (e) {
      alert("採集失敗 (網路錯): " + e.message);
      btn.disabled = false; btn.innerHTML = orig;
    }
  };

  // 採集狀態查詢 — 不用 ssh 到 host 跑 mongosh, 前端按鈕就能看 (v3.17.10.3+)
  window.depShowCollectStatus = async function () {
    try {
      const r = await fetch("/api/dependencies/collect/status/latest", { credentials: "include" });
      if (r.status === 401) { alert("未登入或 session 過期\n請重新登入後再試"); return; }
      if (r.status === 404) { alert("還沒任何採集紀錄\n按「📡 採集」觸發第一次採集"); return; }
      const res = await r.json();
      if (!res.success) { alert("查狀態失敗: " + (res.error || "")); return; }
      const d = res.data || {};
      const fmt = function (t) { return t ? new Date(t).toLocaleString("sv-SE") : "-"; };
      const lines = [
        "最新採集 run_id: " + (d.run_id || "-"),
        "",
        "status:        " + (d.status || "-"),
        "started_at:    " + fmt(d.started_at),
        "finished_at:   " + fmt(d.finished_at),
        "triggered_by:  " + (d.triggered_by || "-"),
        "limit:         " + (d.limit || "-"),
        "edges_added:   " + (d.edges_added || 0),
        "edges_updated: " + (d.edges_updated || 0),
        "host_count:    " + (d.host_count || "-"),
        "error:         " + (d.error || "-"),
      ];
      if (d.status === "success" && (d.edges_added > 0 || d.edges_updated > 0)) {
        lines.push("", "✓ 已寫入邊資料 — 按「🔄 重整」看新拓撲");
      } else if (d.status === "running") {
        lines.push("", "⏳ 採集中, 1-3 分鐘後再按「📊 狀態」");
      } else if (d.status === "failed") {
        lines.push("", "✗ 採集失敗 — 看 error 欄訊息或 ssh 到 host 看 logs/dep_collect_*.log");
      }
      alert(lines.join("\n"));
    } catch (e) { alert("查狀態失敗 (網路錯): " + e.message); }
  };

  function toVisNode(n, view) {
    const tier = (n.tier || "C").toUpperCase();
    const isUnknown = !!n._unknown;
    const colors = isUnknown
      ? { background: "#ffe5b4", border: "#f5a623" }
      : tierColor(tier);

    let id, label;
    if (view === "host") {
      id = n.id || n.hostname || n.system_id;
      label = (n.hostname || id) + (n.ip ? "\n" + n.ip : "") + (n.system_name ? "\n[" + n.system_name + "]" : "");
    } else if (view === "ip") {
      id = n.id || n.ip;
      label = (n.ip || id) + (n.hostname ? "\n" + n.hostname : "") + (n.label_extra ? "\n[" + n.label_extra + "]" : "");
    } else {
      id = n.system_id;
      label = (n.display_name || n.system_id) + (n.host_refs && n.host_refs.length ? "\n(" + n.host_refs.length + " hosts)" : "");
    }

    return {
      id: id,
      label: label,
      title: nodeTooltip(n, view),
      color: colors,
      _raw: n,
    };
  }

  function tierColor(tier) {
    if (tier === "A") return { background: "#fde0e0", border: "#e74c3c" };
    if (tier === "B") return { background: "#fff3cd", border: "#f0ad4e" };
    return { background: "#e8f4ea", border: "#5cb85c" };
  }

  function nodeTooltip(n, view) {
    const lines = [];
    if (view === "host") {
      lines.push("主機: " + (n.hostname || n.id));
      if (n.ip) lines.push("IP: " + n.ip);
      if (n.os) lines.push("OS: " + n.os);
      if (n.system_name) lines.push("所屬系統: " + n.system_name + " (" + n.system_id + ")");
    } else if (view === "ip") {
      lines.push("IP: " + (n.ip || n.id));
      if (n.hostname) lines.push("Hostname: " + n.hostname);
      if (n.system_id) lines.push("所屬系統: " + n.system_id);
      if (n.os) lines.push("OS: " + n.os);
    } else {
      lines.push((n.display_name || n.system_id) + " (" + n.system_id + ")");
      lines.push("級別: " + (n.tier || "C") + "  類別: " + (n.category || "AP"));
      if (n.owner) lines.push("負責人: " + n.owner);
      if (n.host_refs && n.host_refs.length) lines.push("主機: " + n.host_refs.join(", "));
      if (n.description) lines.push(n.description);
    }
    return lines.join("\n");
  }

  function toVisEdge(e) {
    const isAuto = e.source === "ss-tunp";
    const unconfirmed = isAuto && e.manual_confirmed === false;
    return {
      id: e.id,
      from: e.from,
      to: e.to,
      label: e.port ? String(e.port) : "",
      dashes: isAuto,
      width: unconfirmed ? 1 : 2,
      color: unconfirmed ? { color: "#f5a623" } : undefined,
      title: edgeTooltip(e),
      _raw: e,
    };
  }

  function edgeTooltip(e) {
    return [
      e.from + " → " + e.to,
      "類型: " + (e.relation_type || "unknown") + "  " + (e.protocol || "TCP") + ":" + (e.port || "-"),
      "來源: " + (e.source || "manual") + (e.manual_confirmed ? " (已確認)" : " (待確認)"),
      e.description || "",
    ].filter(Boolean).join("\n");
  }

  // ----- 節點選取 -----
  function onNodeSelect(nodeId) {
    if (!nodeId) return;
    _selectedId = nodeId;
    document.getElementById("dep-side-empty").style.display = "none";
    document.getElementById("dep-side-detail").style.display = "block";
    const simBtn = document.getElementById("dep-simulate-btn");
    if (simBtn) { simBtn.disabled = false; simBtn.removeAttribute("title"); }

    // 從 cache 找 node raw, host/ip 模式下用 _raw.system_id 拉詳情
    const cached = _allNodesCache.find(function (n) { return (n.system_id === nodeId) || (n.hostname === nodeId) || (n.ip === nodeId) || (n.id === nodeId); });
    const sysIdForDetail = cached ? (cached.system_id || nodeId) : nodeId;

    if (cached) fillDetail(cached);
    if (sysIdForDetail && !sysIdForDetail.startsWith("UNKNOWN-") && !sysIdForDetail.startsWith("EXT-")) {
      fetch("/api/dependencies/systems/" + encodeURIComponent(sysIdForDetail), { credentials: "include" })
        .then(function (r) { return r.json(); })
        .then(function (res) { if (res.success) fillDetail(res.data); })
        .catch(function () {});
    }

    // 影響分析 (用 system_id, host/ip 模式撈所屬系統)
    if (sysIdForDetail) {
      fetch("/api/dependencies/impact?system_id=" + encodeURIComponent(sysIdForDetail) + "&depth=2", { credentials: "include" })
        .then(function (r) { return r.json(); })
        .then(function (res) {
          if (res.success) renderList("dep-detail-downstream", res.data.affected_systems);
        });
      fetch("/api/dependencies/upstream?system_id=" + encodeURIComponent(sysIdForDetail) + "&depth=2", { credentials: "include" })
        .then(function (r) { return r.json(); })
        .then(function (res) {
          if (res.success) renderList("dep-detail-upstream", res.data.affected_systems);
        });
    }
  }

  function fillDetail(n) {
    // 兼容 system / host / ip 三種視圖的 node raw shape
    const name = n.display_name || n.system_name || n.hostname || n.system_id || n.ip || n.id || "—";
    const idStr = n.system_id || n.hostname || n.ip || n.id || "—";
    document.getElementById("dep-detail-name").textContent = name;
    document.getElementById("dep-detail-id").textContent = idStr;
    const tierEl = document.getElementById("dep-detail-tier");
    const t = (n.tier || "C").toUpperCase();
    tierEl.textContent = t;
    tierEl.className = "dep-tier-badge dep-tier-" + t;
    document.getElementById("dep-detail-category").textContent = n.category || "—";
    document.getElementById("dep-detail-owner").textContent = n.owner || "—";
    let hostsTxt = "—";
    if (n.host_refs && n.host_refs.length) hostsTxt = n.host_refs.join(", ");
    else if (n.hostname && n.ip) hostsTxt = n.hostname + " (" + n.ip + ")";
    else if (n.hostname) hostsTxt = n.hostname;
    else if (n.ip) hostsTxt = n.ip;
    document.getElementById("dep-detail-hosts").textContent = hostsTxt;
    document.getElementById("dep-detail-desc").textContent = n.description || n.os || "";
  }

  function renderList(elId, items) {
    const el = document.getElementById(elId);
    if (!el) return;
    if (!items || !items.length) { el.innerHTML = '<span class="dep-impact-empty">無</span>'; return; }
    el.innerHTML = items.map(function (it) {
      return '<div class="dep-impact-item">' +
        '<span class="dep-impact-level">L' + it.level + '</span>' +
        '<span class="dep-impact-id" onclick="depFocusOn(\'' + escapeHtml(it.system_id) + '\')">' + escapeHtml(it.system_id) + '</span>' +
        '</div>';
    }).join("");
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  // ----- 操作 -----
  window.depSearch = function (q) {
    q = (q || "").trim().toLowerCase();
    if (!_nodes) return;
    const all = _nodes.get();
    if (!q) {
      _network.unselectAll();
      return;
    }
    const matched = all.filter(function (n) {
      const r = n._raw || {};
      return (n.id || "").toLowerCase().indexOf(q) >= 0 ||
        (r.display_name || "").toLowerCase().indexOf(q) >= 0 ||
        (r.owner || "").toLowerCase().indexOf(q) >= 0 ||
        ((r.host_refs || []).join(" ").toLowerCase().indexOf(q) >= 0);
    });
    if (matched.length) {
      _network.selectNodes(matched.map(function (n) { return n.id; }));
      _network.fit({ nodes: matched.map(function (n) { return n.id; }), animation: true });
      onNodeSelect(matched[0].id);
    }
  };

  window.depFitView = function () { if (_network) _network.fit({ animation: true }); };

  window.depFocusOn = function (systemId) {
    if (!_network || !_nodes) return;
    if (!_nodes.get(systemId)) {
      _selectedId = systemId;
      depReload();
      return;
    }
    _network.selectNodes([systemId]);
    _network.focus(systemId, { scale: 1.2, animation: true });
    onNodeSelect(systemId);
  };

  window.depFocusSelected = function () {
    if (_selectedId) depFocusOn(_selectedId);
  };

  window.depExpandNeighbors = function () {
    if (!_selectedId) return;
    depReload();
  };

  // Stage 1 預先實作: 模擬故障 (Stage 2 會加動畫)
  window.depSimulateFailure = function () {
    if (!_selectedId || !_nodes) return;
    fetch("/api/dependencies/impact?system_id=" + encodeURIComponent(_selectedId) + "&depth=4", { credentials: "include" })
      .then(function (r) { return r.json(); })
      .then(function (res) {
        if (!res.success) return;
        const failed = res.data.affected_systems || [];
        // 染中心節點
        _nodes.update({ id: _selectedId, color: { background: "#ff5252", border: "#b71c1c" }, font: { color: "#fff" } });
        // 階梯式染下游 (Stage 2 會做漸進動畫,這裡先一次染)
        failed.forEach(function (item) {
          if (_nodes.get(item.system_id)) {
            setTimeout(function () {
              _nodes.update({ id: item.system_id, color: { background: "#ff8a8a", border: "#c62828" } });
            }, 200 * item.level);
          }
        });
      });
  };

  window.depReset = function () {
    if (!_nodes) return;
    const all = _nodes.get();
    all.forEach(function (n) {
      const raw = n._raw || {};
      _nodes.update({ id: n.id, color: tierColor((raw.tier || "C").toUpperCase()), font: { color: "#222" } });
    });
  };
})();
