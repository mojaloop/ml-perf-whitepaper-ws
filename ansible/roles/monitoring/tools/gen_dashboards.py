import json, os

OUTDIR = "/Users/shashi/Modusbox/DEV/ML/dev/perf-test/TESTS/ml-perf-whitepaper-ws/ansible/roles/monitoring/files/dashboards"

DS = {"uid": "${DS_PROMETHEUS}"}

def target(expr, legend, refId="A"):
    return {"datasource": DS, "expr": expr, "legendFormat": legend, "refId": refId}

def with_p99(p95_panel):
    """Clone a '... p95' panel into a sibling '... p99' panel (0.95 -> 0.99 in every target expr)."""
    import copy
    p99_panel = copy.deepcopy(p95_panel)
    p99_panel["title"] = p95_panel["title"].replace("p95", "p99")
    for t in p99_panel["targets"]:
        t["expr"] = t["expr"].replace("0.95,", "0.99,")
    return p99_panel

def text_panel(title, markdown, h=3, y=0):
    return {
        "type": "text",
        "title": title,
        "gridPos": {"h": h, "w": 24, "x": 0, "y": y},
        "options": {"mode": "markdown", "content": markdown},
    }

def panel(title, targets, unit="s", desc="", h=8, y=0, fill=20, thresholds=None, stack=False, legend_calcs=("mean","max")):
    thresholds = thresholds or [{"color": "green", "value": None}]
    for i, t in enumerate(targets):
        t["refId"] = chr(ord("A") + i)
    return {
        "type": "timeseries",
        "title": title,
        "description": desc,
        "datasource": DS,
        "gridPos": {"h": h, "w": 24, "x": 0, "y": y},
        "fieldConfig": {
            "defaults": {
                "unit": unit,
                "min": 0,
                "custom": {
                    "drawStyle": "line",
                    "lineWidth": 1,
                    "fillOpacity": fill,
                    "spanNulls": True,
                    "showPoints": "never",
                    "stacking": {"mode": "normal" if stack else "none"},
                },
                "thresholds": {"mode": "absolute", "steps": thresholds},
            },
            "overrides": [],
        },
        "options": {
            "legend": {"displayMode": "table", "placement": "right", "calcs": list(legend_calcs)},
            "tooltip": {"mode": "multi", "sort": "desc"},
        },
        "targets": targets,
    }

def expand_with_p99(panels):
    """Insert a p99 sibling panel immediately after every '... p95' panel."""
    out = []
    for p in panels:
        out.append(p)
        if "p95" in p.get("title", ""):
            out.append(with_p99(p))
    return out

def dashboard(title, uid, panels_list, tags):
    y = 0
    for p in panels_list:
        p["gridPos"]["y"] = y
        y += p["gridPos"]["h"]
    return {
        "__requires": [
            {"type": "grafana", "id": "grafana", "name": "Grafana", "version": "10.0.0"},
            {"type": "panel", "id": "timeseries", "name": "Time series", "version": ""},
            {"type": "datasource", "id": "prometheus", "name": "Prometheus", "version": "1.0.0"},
        ],
        "annotations": {
            "list": [
                {
                    "builtIn": 1,
                    "datasource": {"type": "grafana", "uid": "-- Grafana --"},
                    "enable": True,
                    "hide": True,
                    "iconColor": "rgba(0, 211, 255, 1)",
                    "name": "Annotations & Alerts",
                    "type": "dashboard",
                }
            ]
        },
        "editable": True,
        "fiscalYearStartMonth": 0,
        "graphTooltip": 1,
        "id": None,
        "links": [],
        "panels": panels_list,
        "refresh": "30s",
        "schemaVersion": 39,
        "tags": tags,
        "templating": {
            "list": [
                {
                    "name": "DS_PROMETHEUS",
                    "label": "Prometheus",
                    "type": "datasource",
                    "query": "prometheus",
                    "refresh": 1,
                    "current": {"selected": False, "text": "Prometheus", "value": "Prometheus"},
                    "options": [],
                }
            ]
        },
        "time": {"from": "now-1h", "to": "now"},
        "timepicker": {},
        "timezone": "utc",
        "title": title,
        "uid": uid,
        "version": 1,
    }

def write(fname, d):
    path = os.path.join(OUTDIR, fname)
    with open(path, "w") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
    print("wrote", path)

# ---------------------------------------------------------------------------
# 1. K6 Transaction Latency (client-observed)
# ---------------------------------------------------------------------------
k6_panels = [
    panel(
        "End-to-end transaction latency (p50/p95/p99)",
        [
            target('histogram_quantile(0.50, sum(rate(k6_e2e_time_seconds[$__rate_interval])))', "p50"),
            target('histogram_quantile(0.95, sum(rate(k6_e2e_time_seconds[$__rate_interval])))', "p95"),
            target('histogram_quantile(0.99, sum(rate(k6_e2e_time_seconds[$__rate_interval])))', "p99"),
        ],
        unit="s",
        desc="Client-observed (k6) end-to-end transaction latency. This is the SLA gate metric (<1s p99), not internal service processing time.",
        thresholds=[{"color": "green", "value": None}, {"color": "red", "value": 1}],
    ),
    panel(
        "Latency by phase (p99): discovery / quote / transfer",
        [
            target('histogram_quantile(0.99, sum(rate(k6_discovery_time_seconds[$__rate_interval])))', "discovery p99"),
            target('histogram_quantile(0.99, sum(rate(k6_quote_time_seconds[$__rate_interval])))', "quote p99"),
            target('histogram_quantile(0.99, sum(rate(k6_transfer_time_seconds[$__rate_interval])))', "transfer p99"),
        ],
        unit="s",
        desc="Client-observed latency per FSPIOP phase — discovery (party lookup), quote, transfer. Sum of all three legs ≈ e2e time.",
    ),
    panel(
        "Throughput: target vs actual TPS",
        [
            target('sum(rate(k6_iterations_total[$__rate_interval]))', "actual TPS (completed iterations)"),
            target('sum(rate(k6_completed_transactions_total[$__rate_interval]))', "completed transactions/s"),
        ],
        unit="reqps",
        desc="Actual sustained throughput vs the k6 target arrival rate. A gap here means the system can't keep up with the requested TPS.",
    ),
    panel(
        "Dropped iterations (backpressure signal)",
        [target('sum(rate(k6_dropped_iterations_total[$__rate_interval]))', "dropped/s")],
        unit="ops",
        desc="k6 drops an iteration when a VU is still busy with the previous one at the next scheduled tick — the clearest signal of the system falling behind the target rate.",
        thresholds=[{"color": "green", "value": None}, {"color": "red", "value": 1}],
    ),
    panel(
        "Failure rate",
        [
            target('sum(rate(k6_failed_transactions_total[$__rate_interval]))', "failed transactions/s"),
            target('sum(rate(k6_http_req_failed_rate[$__rate_interval]))', "http req failed rate"),
        ],
        unit="ops",
        desc="Transaction and HTTP-level failure rate over time.",
    ),
    panel(
        "Active VUs",
        [target('max(k6_vus)', "VUs"), target('max(k6_vus_max)', "VUs max configured")],
        unit="short",
        desc="Virtual users in flight — rising VUs at flat TPS is itself a backpressure signal (more concurrency needed to sustain the same throughput).",
    ),
]
write("k6-transaction-latency.json", dashboard(
    "K6 Transaction Latency (Client-Observed)", "k6-transaction-latency", k6_panels,
    ["k6", "latency", "whitepaper"],
))

# ---------------------------------------------------------------------------
# 2. mTLS / Mesh Overhead
# ---------------------------------------------------------------------------
mtls_panels = [
    panel(
        "Traffic by mTLS connection security policy",
        [target('sum by (connection_security_policy) (rate(istio_requests_total{reporter="destination"}[$__rate_interval]))', "{{connection_security_policy}}")],
        unit="reqps",
        desc="Breaks down request volume by Istio's reported connection security: mutual_tls (mesh mTLS) vs none (plaintext). Filtered to reporter=\"destination\" — only the receiving proxy can determine the actual security policy (the source-side proxy always reports \"unknown\" for this field since it can't see how the connection was ultimately secured, which double-counts volume and looks like a fake security gap if not filtered out).",
        stack=True,
    ),
    panel(
        "istio-proxy (sidecar) CPU usage by pod",
        [target('sum by (pod) (rate(container_cpu_usage_seconds_total{container="istio-proxy"}[$__rate_interval]))', "{{pod}}")],
        unit="short",
        desc="CPU cost of the edge/sidecar mTLS layer, per pod. Core input to the mesh-cost-vs-plaintext comparison.",
    ),
    panel(
        "istio-proxy (sidecar) memory usage by pod",
        [target('sum by (pod) (container_memory_working_set_bytes{container="istio-proxy"})', "{{pod}}")],
        unit="bytes",
        desc="Memory cost of sidecar mTLS per pod (instantaneous).",
    ),
    panel(
        "ztunnel CPU usage by node (ambient mesh only)",
        [target('sum by (pod) (rate(container_cpu_usage_seconds_total{pod=~"ztunnel.*"}[$__rate_interval]))', "{{pod}}")],
        unit="short",
        desc="Per-node ztunnel proxy CPU cost — only populated when running the ambient-mesh scenario (ztunnel is not deployed in the WireGuard/sidecar-only scenarios).",
    ),
    panel(
        "Envoy active connections (sidecar + ingressgateway)",
        [target('envoy_server_total_connections', "{{pod}}")],
        unit="short",
        desc="Gauge, not a rate — current open connections per Envoy instance. Useful for spotting connection churn/leaks.",
    ),
    panel(
        "mTLS request duration overhead (p99, by destination workload)",
        [target('histogram_quantile(0.99, sum by (le, destination_workload) (rate(istio_request_duration_milliseconds_bucket{reporter="destination"}[$__rate_interval])))', "{{destination_workload}}")],
        unit="ms",
        desc="Mesh-observed request duration per destination service — compare across scenarios (plaintext / WireGuard / ambient) to isolate the mesh's own latency contribution. Filtered to reporter=\"destination\" (server-side processing time only) so source- and destination-side samples aren't mixed into the same percentile calculation.",
    ),
]
write("mtls-mesh-overhead.json", dashboard(
    "mTLS / Mesh Overhead", "mtls-mesh-overhead", mtls_panels,
    ["mtls", "istio", "security", "whitepaper"],
))

# ---------------------------------------------------------------------------
# 3. Service Mesh Hop Latency
# ---------------------------------------------------------------------------
hop_panels = [
    panel(
        "Request rate by hop (source → destination)",
        [target('sum by (source_workload, destination_workload) (rate(istio_requests_total{reporter="destination"}[$__rate_interval]))', "{{source_workload}} → {{destination_workload}}")],
        unit="reqps",
        desc="Traffic volume per mesh hop, both switch-internal service-to-service calls and DFSP↔switch edge traffic. Filtered to reporter=\"destination\" to avoid double-counting each request (source + destination both emit a sample per request).",
        stack=True,
    ),
    panel(
        "Hop latency p50 (by source → destination)",
        [target('histogram_quantile(0.50, sum by (le, source_workload, destination_workload) (rate(istio_request_duration_milliseconds_bucket{reporter="destination"}[$__rate_interval])))', "{{source_workload}} → {{destination_workload}}")],
        unit="ms",
        desc="Filtered to reporter=\"destination\" (server-side duration) so source- and destination-side samples aren't mixed in the same percentile.",
    ),
    panel(
        "Hop latency p99 (by source → destination)",
        [target('histogram_quantile(0.99, sum by (le, source_workload, destination_workload) (rate(istio_request_duration_milliseconds_bucket{reporter="destination"}[$__rate_interval])))', "{{source_workload}} → {{destination_workload}}")],
        unit="ms",
        desc="The per-hop breakdown that explains WHERE in the switch's internal call graph the e2e tail comes from — more actionable than the black-box k6 client view. Filtered to reporter=\"destination\".",
    ),
    panel(
        "Non-2xx response rate by hop",
        [target('sum by (source_workload, destination_workload, response_code) (rate(istio_requests_total{response_code!~"2..", reporter="destination"}[$__rate_interval]))', "{{source_workload}}→{{destination_workload}} [{{response_code}}]")],
        unit="reqps",
        desc="Error responses per hop — isolates which service pair is producing failures, not just the aggregate client-side failure rate. Filtered to reporter=\"destination\" to avoid double-counting.",
    ),
]
write("service-mesh-hop-latency.json", dashboard(
    "Service Mesh Hop Latency", "service-mesh-hop-latency", hop_panels,
    ["istio", "latency", "mesh", "whitepaper"],
))

print("done: k6, mtls, hop-latency")
