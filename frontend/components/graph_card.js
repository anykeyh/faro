// Graph card — line chart using SVG (vector, no pixelation on zoom)

var LINE_COLORS = [
  "#d4a843",
  "#4a9e6b",
  "#7a8ba8",
  "#c9922a",
  "#b94a4a",
  "#8b7ba8",
  "#5a8a7a",
  "#a38333",
];

var AXIS_LABEL_WIDTH = 44;
var AXIS_LABEL_HEIGHT = 18;
var AXIS_PAD = 10;
var RANGE_OPTIONS = [
  { label: "7d", minutes: 7 * 24 * 60 },
  { label: "3d", minutes: 3 * 24 * 60 },
  { label: "24h", minutes: 24 * 60 },
  { label: "6h", minutes: 6 * 60 },
  { label: "1h", minutes: 60 },
  { label: "30m", minutes: 30 },
  { label: "5m", minutes: 5 },
];

function fmtAxisTime(date, totalMinutes) {
  var h = String(date.getHours()).padStart(2, "0");
  var m = String(date.getMinutes()).padStart(2, "0");
  var s = String(date.getSeconds()).padStart(2, "0");
  if (totalMinutes >= 24 * 60) {
    var month = String(date.getMonth() + 1).padStart(2, "0");
    var day = String(date.getDate()).padStart(2, "0");
    return month + "/" + day + " " + h + ":" + m;
  }
  if (totalMinutes >= 60) {
    return h + ":" + m;
  }
  return h + ":" + m + ":" + s;
}

// Format byte/number for graph labels
function friendlyBytes(n, inKb) {
  if (n === null || n === undefined) return "—";
  var bytes = inKb ? n * 1024 : n;
  if (bytes < 1024) return bytes.toFixed(0) + " B";
  var kb = bytes / 1024;
  if (kb < 1024) return kb.toFixed(1) + " KB";
  var mb = kb / 1024;
  if (mb < 1024) return mb.toFixed(1) + " MB";
  var gb = mb / 1024;
  if (gb < 1024) return gb.toFixed(2) + " GB";
  var tb = gb / 1024;
  return tb.toFixed(2) + " TB";
}

function esc(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// ── Hover tooltip ──────────────────────────────────────────

// Given an X pixel coordinate and chart state, find the nearest timestamp
// across all datasets and return { ts, x, items: [{name, value, color}] } or null.
function findNearest(svgX, state) {
  var bestDist = Infinity;
  var bestTs = null;
  var bestX = null;

  // Find the single nearest data point's timestamp
  state.datasets.forEach(function (ds) {
    ds.pts.forEach(function (p) {
      var dx = Math.abs(p.svgX - svgX);
      if (dx < bestDist) {
        bestDist = dx;
        bestTs = p.ts;
        bestX = p.svgX;
      }
    });
  });

  if (bestTs === null) return null;

  // Collect ALL datasets' values that share this timestamp (or closest)
  var items = [];
  state.datasets.forEach(function (ds) {
    // Find the point in this dataset closest to bestTs
    var closest = null;
    var closeDist = Infinity;
    ds.pts.forEach(function (p) {
      var d = Math.abs(p.ts - bestTs);
      if (d < closeDist) {
        closeDist = d;
        closest = p;
      }
    });
    if (closest) {
      items.push({ name: ds.name, value: closest.value, color: ds.color });
    }
  });

  return { ts: bestTs, x: bestX, items: items };
}

// Build the SVG content for a card.  Also populates state.datasets with
// computed SVG coordinates for hover tracking.
function buildSVG(card, containerWidth, containerHeight, state) {
  state.datasets = [];

  if (!card.metrics || card.metrics.length === 0) return "";

  var rangeMinutes = card.range || 60;
  var now = Date.now();
  var windowStart = now - rangeMinutes * 60 * 1000;
  var windowEnd = now;
  var windowRange = windowEnd - windowStart;

  var W = containerWidth || 600;
  var H = containerHeight || 200;
  var chartL = AXIS_LABEL_WIDTH;
  var chartR = W - AXIS_PAD;
  var chartT = AXIS_PAD;
  var chartB = H - AXIS_LABEL_HEIGHT - AXIS_PAD;
  var chartW = chartR - chartL;
  var chartH = chartB - chartT;

  // Detect metric type for axis formatting
  var isPct = card.metrics.some(function (m) {
    return /_pct$/.test(m);
  });
  var isBytes = card.metrics.some(function (m) {
    return /_(kb|bytes)$/.test(m);
  });
  var isKb = card.metrics.some(function (m) {
    return /_kb$/.test(m);
  });

  if (chartW < 10 || chartH < 10) return "";

  // Build datasets
  var datasets = [];
  card.metrics.forEach(function (metric, idx) {
    var raw = store.getSeries(card.adapter, metric);
    if (!raw || raw.length < 2) return;

    var pts = [];
    raw.forEach(function (s) {
      if (s.avg === null || s.avg === undefined || !s.resolved_at) return;
      var t = new Date(s.resolved_at).getTime();
      if (t < windowStart || t > windowEnd) return;
      pts.push({ value: s.avg, ts: t });
    });
    if (pts.length < 2) return;

    datasets.push({
      name: metric,
      pts: pts,
      color: LINE_COLORS[idx % LINE_COLORS.length],
    });
  });

  if (datasets.length === 0) return "";

  // Global Y range
  var minVal = datasets[0].pts[0].value;
  var maxVal = datasets[0].pts[0].value;
  datasets.forEach(function (ds) {
    ds.pts.forEach(function (p) {
      if (p.value < minVal) minVal = p.value;
      if (p.value > maxVal) maxVal = p.value;
    });
  });
  var valRange = maxVal - minVal || 1;

  function xPos(ts) {
    return chartL + ((ts - windowStart) / windowRange) * chartW;
  }
  function yPos(val) {
    return chartT + (1 - (val - minVal) / valRange) * chartH;
  }

  // Store computed positions in state for hover
  datasets.forEach(function (ds) {
    ds.pts.forEach(function (p) {
      p.svgX = xPos(p.ts);
      p.svgY = yPos(p.value);
    });
  });
  state.datasets = datasets;
  state.chartT = chartT;
  state.chartB = chartB;
  state.chartL = chartL;
  state.chartR = chartR;
  state.isPct = isPct;
  state.isBytes = isBytes;
  state.isKb = isKb;

  // ── Build SVG string ─────────────────────────────────────

  var parts = [];

  // Background (catches mouse events)
  parts.push(
    '<rect x="0" y="0" width="' +
      W +
      '" height="' +
      H +
      '" fill="transparent" />',
  );

  // Y-axis grid lines + labels
  var tickCount = 4;
  for (var i = 0; i <= tickCount; i++) {
    var t = i / tickCount;
    var y = chartT + t * chartH;
    var val = maxVal - t * valRange;
    var label;
    if (isBytes) {
      label = friendlyBytes(val, isKb);
    } else {
      var displayVal = isPct ? val * 100 : val;
      label =
        (displayVal >= 1000 ? displayVal.toFixed(0) : displayVal.toFixed(1)) +
        (isPct ? "%" : "");
    }
    parts.push(
      '<line x1="' +
        chartL +
        '" y1="' +
        y +
        '" x2="' +
        chartR +
        '" y2="' +
        y +
        '" stroke="#2a2e3a" stroke-width="1" />',
    );
    parts.push(
      '<text x="' +
        (chartL - 6) +
        '" y="' +
        y +
        '" fill="#9e968a" font-family="sans-serif" font-size="11" text-anchor="end" dominant-baseline="middle">' +
        esc(label) +
        "</text>",
    );
  }

  // Y-axis unit label
  if (isBytes) {
    var unitLabel = isKb ? "KB" : "Bytes";
    parts.push(
      '<text x="' +
        (chartL - 4) +
        '" y="' +
        (chartT - 2) +
        '" fill="#9e968a" font-family="sans-serif" font-size="9" text-anchor="end" dominant-baseline="baseline">' +
        esc(unitLabel) +
        "</text>",
    );
  } else if (isPct) {
    parts.push(
      '<text x="' +
        (chartL - 4) +
        '" y="' +
        (chartT - 2) +
        '" fill="#9e968a" font-family="sans-serif" font-size="9" text-anchor="end" dominant-baseline="baseline">%</text>',
    );
  }

  // X-axis time labels
  for (var i = 0; i <= tickCount; i++) {
    var t = i / tickCount;
    var x = chartL + t * chartW;
    var ts = windowStart + t * windowRange;
    parts.push(
      '<text x="' +
        x +
        '" y="' +
        (chartB + 4) +
        '" fill="#9e968a" font-family="sans-serif" font-size="11" text-anchor="middle" dominant-baseline="hanging">' +
        esc(fmtAxisTime(new Date(ts), rangeMinutes)) +
        "</text>",
    );
  }

  // Lines + point markers for each dataset
  datasets.forEach(function (ds) {
    // Compute gap threshold: 3x the expected interval between points
    var expectedInterval = windowRange / ds.pts.length;
    var gapThreshold = Math.max(expectedInterval * 3, 15000); // at least 15s

    var pathParts = [];
    ds.pts.forEach(function (p, i) {
      if (i === 0) {
        pathParts.push("M" + p.svgX.toFixed(1) + " " + p.svgY.toFixed(1));
      } else {
        var prev = ds.pts[i - 1];
        var dt = p.ts - prev.ts;
        if (dt > gapThreshold) {
          // Gap detected — break the segment and mark edges
          // Draw a prominent T-shaped marker at each gap edge
          var markLen = 10;
          // Left edge (previous point)
          parts.push(
            '<line x1="' +
              prev.svgX.toFixed(1) +
              '" y1="' +
              (prev.svgY - markLen).toFixed(1) +
              '" x2="' +
              prev.svgX.toFixed(1) +
              '" y2="' +
              (prev.svgY + markLen).toFixed(1) +
              '" stroke="#b94a4a" stroke-width="2" />',
          );
          // Right edge (current point)
          parts.push(
            '<line x1="' +
              p.svgX.toFixed(1) +
              '" y1="' +
              (p.svgY - markLen).toFixed(1) +
              '" x2="' +
              p.svgX.toFixed(1) +
              '" y2="' +
              (p.svgY + markLen).toFixed(1) +
              '" stroke="#b94a4a" stroke-width="2" />',
          );
          pathParts.push("M" + p.svgX.toFixed(1) + " " + p.svgY.toFixed(1));
        } else {
          pathParts.push("L" + p.svgX.toFixed(1) + " " + p.svgY.toFixed(1));
        }
      }
    });

    parts.push(
      '<path d="' +
        pathParts.join(" ") +
        '" fill="none" stroke="' +
        ds.color +
        '" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" />',
    );

    ds.pts.forEach(function (p) {
      parts.push(
        '<circle cx="' +
          p.svgX.toFixed(1) +
          '" cy="' +
          p.svgY.toFixed(1) +
          '" r="3" fill="' +
          ds.color +
          '" />',
      );
    });
  });

  // Legend
  var legendX = chartL + 4;
  var legendY = chartT + 4;
  datasets.forEach(function (ds) {
    parts.push(
      '<rect x="' +
        legendX +
        '" y="' +
        (legendY + 2) +
        '" width="8" height="8" fill="' +
        ds.color +
        '" />',
    );
    parts.push(
      '<text x="' +
        (legendX + 12) +
        '" y="' +
        legendY +
        '" fill="#9e968a" font-family="sans-serif" font-size="11" dominant-baseline="hanging">' +
        esc(ds.name) +
        "</text>",
    );
    legendY += 14;
  });

  return (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' +
    W +
    " " +
    H +
    '" width="100%" height="100%">' +
    parts.join("") +
    "</svg>"
  );
}

// Draw (or clear) the hover crosshair and tooltip on the SVG overlay.
function drawHover(svgEl, nearest, state) {
  var overlay = svgEl.querySelector(".hover-overlay");
  if (!nearest) {
    if (overlay) overlay.innerHTML = "";
    return;
  }

  if (!overlay) {
    overlay = document.createElementNS("http://www.w3.org/2000/svg", "g");
    overlay.setAttribute("class", "hover-overlay");
    svgEl.appendChild(overlay);
  }

  var viewW = parseFloat(svgEl.getAttribute("viewBox").split(" ")[2]);
  var x = nearest.x;

  // Crosshair vertical line
  var line = document.createElementNS("http://www.w3.org/2000/svg", "line");
  line.setAttribute("x1", x);
  line.setAttribute("y1", state.chartT);
  line.setAttribute("x2", x);
  line.setAttribute("y2", state.chartB);
  line.setAttribute("stroke", "#9e968a");
  line.setAttribute("stroke-width", "1");
  line.setAttribute("stroke-dasharray", "4,3");

  // Tooltip position
  var tipX = x < viewW / 2 ? x + 12 : x - 12;
  var tipAnchor = x < viewW / 2 ? "start" : "end";
  var timeText = fmtAxisTime(new Date(nearest.ts), 60);

  overlay.innerHTML = "";
  overlay.appendChild(line);

  // For each metric: draw a highlighted circle at its Y + a tooltip line
  var topY = null;
  var bottomY = null;
  nearest.items.forEach(function (item) {
    // Find the SVG Y for this value — need to map through the dataset
    var ptY = null;
    state.datasets.forEach(function (ds) {
      if (ds.name === item.name) {
        ds.pts.forEach(function (p) {
          if (Math.abs(p.ts - nearest.ts) < 1000) {
            ptY = p.svgY;
          }
        });
      }
    });
    if (ptY === null) return;
    if (topY === null || ptY < topY) topY = ptY;
    if (bottomY === null || ptY > bottomY) bottomY = ptY;

    // Circle
    var circle = document.createElementNS(
      "http://www.w3.org/2000/svg",
      "circle",
    );
    circle.setAttribute("cx", x);
    circle.setAttribute("cy", ptY);
    circle.setAttribute("r", "5");
    circle.setAttribute("fill", item.color);
    circle.setAttribute("stroke", "#1a1713");
    circle.setAttribute("stroke-width", "2");
    overlay.appendChild(circle);
  });

  // Tooltip: timestamp header
  var timeEl = document.createElementNS("http://www.w3.org/2000/svg", "text");
  timeEl.setAttribute("x", tipX);
  timeEl.setAttribute("y", topY !== null ? topY - 16 : state.chartT + 4);
  timeEl.setAttribute("fill", "#9e968a");
  timeEl.setAttribute("font-family", "sans-serif");
  timeEl.setAttribute("font-size", "10");
  timeEl.setAttribute("text-anchor", tipAnchor);
  timeEl.setAttribute("dominant-baseline", "auto");
  timeEl.textContent = timeText;
  overlay.appendChild(timeEl);

  // Tooltip: one line per metric, with color swatch
  var lineY = timeEl.getAttribute("y");
  nearest.items.forEach(function (item) {
    var ptY = null;
    state.datasets.forEach(function (ds) {
      if (ds.name === item.name) {
        ds.pts.forEach(function (p) {
          if (Math.abs(p.ts - nearest.ts) < 1000) {
            ptY = p.svgY;
          }
        });
      }
    });
    if (ptY === null) return;

    // Colored circle marker in tooltip
    var dot = document.createElementNS("http://www.w3.org/2000/svg", "circle");
    dot.setAttribute("cx", tipAnchor === "start" ? tipX + 5 : tipX - 5);
    dot.setAttribute("cy", ptY);
    dot.setAttribute("r", "3");
    dot.setAttribute("fill", item.color);
    overlay.appendChild(dot);

    var displayVal;
    var suffix = "";
    if (state.isBytes) {
      displayVal = friendlyBytes(item.value, state.isKb);
    } else {
      displayVal = (state.isPct ? item.value * 100 : item.value).toFixed(1);
      if (state.isPct) suffix = "%";
    }

    // Background rect behind label
    var labelText = item.name + ": " + displayVal + suffix;
    var labelWidth = labelText.length * 7.2;
    var bg = document.createElementNS("http://www.w3.org/2000/svg", "rect");
    bg.setAttribute(
      "x",
      tipAnchor === "start" ? tipX + 8 : tipX - labelWidth - 8,
    );
    bg.setAttribute("y", ptY - 9);
    bg.setAttribute("width", labelWidth + 8);
    bg.setAttribute("height", "18");
    bg.setAttribute("rx", "3");
    bg.setAttribute("fill", "rgba(13, 11, 8, 0.75)");
    bg.setAttribute("stroke", "rgba(47, 42, 35, 0.5)");
    bg.setAttribute("stroke-width", "1");
    overlay.appendChild(bg);

    // Value label next to circle
    var label = document.createElementNS("http://www.w3.org/2000/svg", "text");
    label.setAttribute("x", tipAnchor === "start" ? tipX + 12 : tipX - 12);
    label.setAttribute("y", ptY + 1);
    label.setAttribute("fill", "#e8e2d8");
    label.setAttribute("font-family", "sans-serif");
    label.setAttribute("font-size", "11");
    label.setAttribute("font-weight", "600");
    label.setAttribute("text-anchor", tipAnchor === "start" ? "start" : "end");
    label.setAttribute("dominant-baseline", "middle");
    label.textContent = labelText;
    overlay.appendChild(label);
  });
}

// Parse columnar format { fields, values } into groups of records keyed by metric
function parseColumnar(data) {
  var series = {};
  if (!data || !data.fields || !data.values) return series;
  var fields = data.fields;
  data.values.forEach(function (row) {
    var record = {};
    fields.forEach(function (f, i) {
      record[f] = row[i];
    });
    var metric = record.metric;
    if (!metric) return;
    if (!series[metric]) series[metric] = [];
    series[metric].push(record);
  });
  return series;
}

var GraphCard = {
  oncreate: function (vnode) {
    var card = vnode.attrs.card;
    var state = vnode.state;

    state.updateSVG = function () {
      var container = vnode.dom.querySelector(".svg-chart");
      if (!container) return;
      var parent = container.parentElement;
      var w = parent.clientWidth || 600;
      var h = parent.clientHeight || 200;
      var svg = buildSVG(card, w, h, state);
      container.innerHTML = svg;

      var svgEl = container.querySelector("svg");
      if (svgEl) {
        svgEl.onmousemove = function (e) {
          var rect = svgEl.getBoundingClientRect();
          var svgX =
            ((e.clientX - rect.left) / rect.width) *
            parseFloat(svgEl.getAttribute("viewBox").split(" ")[2]);
          var nearest = findNearest(svgX, state);
          drawHover(svgEl, nearest, state);
        };
        svgEl.onmouseleave = function () {
          drawHover(svgEl, null, state);
        };
      }
    };

    state._fetchData = function () {
      API.query(card.adapter, card.range || 60)
        .then(function (data) {
          var a = store.adapters[card.adapter];
          if (a) {
            a.series = parseColumnar(data);
          }
          state.updateSVG();
          m.redraw();
        })
        .catch(function () {});
    };

    state._fetchData();
    state._lastFetch = Date.now();
  },
  onupdate: function (vnode) {
    var card = vnode.attrs.card;
    var state = vnode.state;
    // Re-fetch if range changed, otherwise just re-render with latest series
    if (state._lastRange !== card.range) {
      state._lastRange = card.range;
      state._fetchData();
    } else if (state.updateSVG) {
      state.updateSVG();
    }
  },
  view: function (vnode) {
    var card = vnode.attrs.card;

    var isDragging = dragState.drag && dragState.drag.id === card.id;
    var isResizing = dragState.resize && dragState.resize.id === card.id;

    return m(
      ".card.card-graph",
      {
        class: [isDragging && "dragging", isResizing && "resizing"]
          .filter(Boolean)
          .join(" "),
        style: {
          left: posX(card.x) + "px",
          top: posY(card.y) + "px",
          width: spanW(card.w) + "px",
          height: spanH(card.h || 1) + "px",
        },
      },
      [
        m(".card-header", [
          m(
            ".card-title",
            {
              onmousedown: function (e) {
                if (e.button !== 0) return;
                e.preventDefault();
                var cardEl = e.currentTarget.parentElement;
                var r = cardEl.getBoundingClientRect();
                dragState.drag = {
                  id: card.id,
                  offsetX: e.clientX - r.left,
                  offsetY: e.clientY - r.top,
                  targetX: card.x,
                  targetY: card.y,
                  canDrop: true,
                };
              },
            },
            [m("span.dot"), m("span", store.cardLabel(card))],
          ),
          m(".card-actions", [
            m(
              "select",
              {
                style:
                  "background:var(--surface-hover);color:var(--text-dim);border:1px solid var(--border);border-radius:4px;font-size:11px;padding:1px 4px;cursor:pointer;",
                onchange: function (e) {
                  store.updateCard(card, {
                    range: parseInt(e.target.value, 10),
                  });
                },
              },
              RANGE_OPTIONS.map(function (opt) {
                return m(
                  "option",
                  {
                    value: opt.minutes,
                    selected: (card.range || 60) === opt.minutes,
                  },
                  opt.label,
                );
              }),
            ),
            m(
              "a.card-action",
              {
                href: "#",
                onclick: function (e) {
                  e.preventDefault();
                  openEditCard(card);
                },
              },
              "\u270E",
            ),
            m(
              "a.card-action",
              {
                href: "#",
                onclick: function (e) {
                  e.preventDefault();
                  if (confirm("Remove this card?")) store.removeCard(card);
                },
              },
              "\u2716",
            ),
          ]),
        ]),
        m(".card-body", [
          m(".svg-chart", { style: "width:100%;height:100%;" }),
        ]),
        m(".resize-handle", {
          onmousedown: function (e) {
            if (e.button !== 0) return;
            e.preventDefault();
            e.stopPropagation();
            dragState.resize = {
              id: card.id,
              startMouseX: e.clientX,
              startMouseY: e.clientY,
              startW: card.w,
              startH: card.h || 1,
              targetW: card.w,
              targetH: card.h || 1,
              canResize: true,
            };
          },
        }),
      ],
    );
  },
};
