import json, os
import sys
sys.path.insert(0, os.path.dirname(__file__))
from gen_dashboards import target, panel, dashboard, write, expand_with_p99, text_panel

# ---------------------------------------------------------------------------
# 4. Central-Ledger (Transfer Legs)
# ---------------------------------------------------------------------------
cl_panels = [
    panel(
        "Transfer Prepare — processing time p95, by leg",
        [
            target('histogram_quantile(0.95, sum by (le) (rate(moja_transfer_prepare_bucket[$__rate_interval])))', "handler ingress"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_domain_transfer_bucket{funcName="prepare"}[$__rate_interval])))', "domain logic"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_model_transfer_bucket[$__rate_interval])))', "model / DB"),
        ],
        unit="s",
        desc="Three-layer breakdown of transfer-prepare processing time: Kafka-handler ingress -> domain logic -> DB model layer. Isolates which layer contributes the most latency.",
    ),
    panel(
        "Transfer Fulfil — processing time p95, by leg",
        [
            target('histogram_quantile(0.95, sum by (le) (rate(moja_transfer_fulfil_bucket[$__rate_interval])))', "handler ingress"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_domain_transfer_bucket{funcName="handlePayeeResponse"}[$__rate_interval])))', "domain logic"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_model_transfer_bucket[$__rate_interval])))', "model / DB"),
        ],
        unit="s",
    ),
    panel(
        "Transfer Position — processing time p95 (single + batch)",
        [
            target('histogram_quantile(0.95, sum by (le) (rate(moja_transfer_position_bucket[$__rate_interval])))', "position"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_transfer_position_batch_bucket[$__rate_interval])))', "position batch"),
        ],
        unit="s",
    ),
    panel(
        "Throughput /sec — prepare / fulfil / position",
        [
            target('sum(rate(moja_transfer_prepare_count[$__rate_interval]))', "prepare"),
            target('sum(rate(moja_transfer_fulfil_count[$__rate_interval]))', "fulfil"),
            target('sum(rate(moja_transfer_position_count[$__rate_interval]))', "position"),
            target('sum(rate(moja_transfer_position_batch_count[$__rate_interval]))', "position batch"),
        ],
        unit="ops",
    ),
    panel(
        "Model cache hit rate (%) — cached participant/transfer lookups",
        [
            target(
                '100 * sum(rate(moja_model_participant_count{queryName=~".*Cached", hit="true"}[$__rate_interval])) '
                '/ sum(rate(moja_model_participant_count{queryName=~".*Cached"}[$__rate_interval]))',
                "participant cache hit %",
            ),
        ],
        unit="percent",
        desc="Share of cached-model lookups served from the in-memory cache vs a DB round-trip.",
    ),
    panel(
        "Error rate (success=false), by leg",
        [
            target('sum(rate(moja_transfer_prepare_count{success="false"}[$__rate_interval]))', "prepare"),
            target('sum(rate(moja_transfer_fulfil_count{success="false"}[$__rate_interval]))', "fulfil"),
            target('sum(rate(moja_domain_transfer_count{success="false"}[$__rate_interval]))', "domain"),
            target('sum(rate(moja_model_transfer_count{success="false"}[$__rate_interval]))', "model"),
        ],
        unit="ops",
    ),
    panel(
        "Event loop lag (p99) by service",
        [target('moja_nodejs_eventloop_lag_p99_seconds{serviceName=~"central-.*"}', "{{serviceName}} - {{pod}}")],
        unit="s",
        desc="V8 event-loop stalls (GC pauses etc.) per central-ledger handler — the historical root cause of e2e p99 tail when log level was set to info.",
    ),
]
cl_panels = expand_with_p99(cl_panels)
write("central-ledger-transfer-legs.json", dashboard(
    "Mojaloop - Central Ledger (Transfer Legs)", "central-ledger-transfer-legs", cl_panels,
    ["central-ledger", "latency", "whitepaper"],
))

# ---------------------------------------------------------------------------
# 5. ALS (Account Lookup Service)
# ---------------------------------------------------------------------------
als_panels = [
    panel(
        "Party lookup — ingress processing time p95",
        [
            target('histogram_quantile(0.95, sum by (le) (rate(moja_ing_getPartiesByTypeAndID_bucket[$__rate_interval])))', "GET /parties"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_ing_putPartiesByTypeAndID_bucket[$__rate_interval])))', "PUT /parties"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_ing_putPartiesErrorByTypeAndID_bucket[$__rate_interval])))', "PUT /parties/error"),
        ],
        unit="s",
    ),
    panel(
        "Domain / oracle layer — processing time p95",
        [
            target('histogram_quantile(0.95, sum by (le) (rate(moja_fetchParticipant_bucket[$__rate_interval])))', "fetchParticipant"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_fetchParticipants_bucket[$__rate_interval])))', "fetchParticipants"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_getParticipant_bucket[$__rate_interval])))', "getParticipant"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_getEndpoint_bucket[$__rate_interval])))', "getEndpoint"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_sendRequest_bucket[$__rate_interval])))', "sendRequest (to DFSP oracle)"),
        ],
        unit="s",
        desc="Domain-layer discovery legs, including the outbound call to the DFSP's oracle simulator (sendRequest) — usually the largest share of discovery latency.",
    ),
    panel(
        "Throughput /sec — party + participant + domain calls",
        [
            target('sum(rate(moja_ing_getPartiesByTypeAndID_count[$__rate_interval]))', "GET /parties"),
            target('sum(rate(moja_ing_putPartiesByTypeAndID_count[$__rate_interval]))', "PUT /parties"),
            target('sum(rate(moja_fetchParticipant_count[$__rate_interval]))', "fetchParticipant"),
            target('sum(rate(moja_sendRequest_count[$__rate_interval]))', "sendRequest"),
        ],
        unit="ops",
    ),
    panel(
        "Error rate (success=false)",
        [
            target('sum(rate(moja_ing_getPartiesByTypeAndID_count{success="false"}[$__rate_interval]))', "GET /parties errors"),
            target('sum(rate(moja_fetchParticipant_count{success="false"}[$__rate_interval]))', "fetchParticipant errors"),
            target('sum(rate(moja_sendRequest_count{success="false"}[$__rate_interval]))', "sendRequest errors"),
        ],
        unit="ops",
    ),
    panel(
        "Event loop lag (p99) + heap used",
        [
            target('moja_nodejs_eventloop_lag_p99_seconds{serviceName="account-lookup-service"}', "{{pod}}"),
        ],
        unit="s",
    ),
    text_panel(
        "Cache Hit Rate — not available",
        "**No cache-hit metric exists for ALS in the current build.** "
        "Unlike Quoting Service (`moja_database_get_cache_value_count`) and Central-Ledger "
        "(`moja_model_participant_count{queryName=~\".*Cached\"}`), ALS emits no cache-hit/miss "
        "counter — confirmed absent by checking the live metric set. This is an instrumentation "
        "gap, not a missing query.",
        h=3,
    ),
]
als_panels = expand_with_p99(als_panels)
write("account-lookup-service-v2.json", dashboard(
    "Mojaloop - ALS", "als-v2", als_panels,
    ["als", "discovery", "latency", "whitepaper"],
))

# ---------------------------------------------------------------------------
# 6. Quoting Service
# ---------------------------------------------------------------------------
qs_panels = [
    panel(
        "Quote ingress — processing time p95",
        [
            target('histogram_quantile(0.95, sum by (le) (rate(moja_quotes_post_bucket[$__rate_interval])))', "POST /quotes"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_quotes_id_put_bucket[$__rate_interval])))', "PUT /quotes/{id}"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_quotes_id_put_error_bucket[$__rate_interval])))', "PUT /quotes/{id}/error"),
        ],
        unit="s",
    ),
    panel(
        "Quote model — processing time p95",
        [target('histogram_quantile(0.95, sum by (le) (rate(moja_model_quote_bucket[$__rate_interval])))', "model")],
        unit="s",
    ),
    panel(
        "Throughput /sec",
        [
            target('sum(rate(moja_quotes_post_count[$__rate_interval]))', "POST /quotes"),
            target('sum(rate(moja_quotes_id_put_count[$__rate_interval]))', "PUT /quotes/{id}"),
        ],
        unit="ops",
    ),
    panel(
        "Cache hit rate (%) — by query",
        [
            target(
                '100 * sum by (queryName) (rate(moja_database_get_cache_value_count{hit="true"}[$__rate_interval])) '
                '/ sum by (queryName) (rate(moja_database_get_cache_value_count[$__rate_interval]))',
                "{{queryName}}",
            ),
        ],
        unit="percent",
        desc="Per-query-type cache hit rate (e.g. getParticipant lookups cached by the quoting service).",
    ),
    panel(
        "Error rate (success=false)",
        [
            target('sum(rate(moja_quotes_post_count{success="false"}[$__rate_interval]))', "POST /quotes errors"),
            target('sum(rate(moja_quotes_id_put_count{success="false"}[$__rate_interval]))', "PUT /quotes/{id} errors"),
        ],
        unit="ops",
    ),
    panel(
        "Event loop lag (p99)",
        [target('moja_nodejs_eventloop_lag_p99_seconds{serviceName="quoting-service"}', "{{pod}}")],
        unit="s",
    ),
]
qs_panels = expand_with_p99(qs_panels)
write("quoting-service-v2.json", dashboard(
    "Mojaloop - Quoting Service", "quoting-service-v2", qs_panels,
    ["quoting-service", "latency", "whitepaper"],
))

# ---------------------------------------------------------------------------
# 7. ML-API-Adapter
# ---------------------------------------------------------------------------
ml_panels = [
    panel(
        "Transfer prepare/fulfil handler — processing time p95",
        [
            target('histogram_quantile(0.95, sum by (le) (rate(moja_ml_transfer_prepare_bucket[$__rate_interval])))', "prepare"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_ml_transfer_fulfil_bucket[$__rate_interval])))', "fulfil"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_ml_transfer_fulfil_error_bucket[$__rate_interval])))', "fulfil error"),
        ],
        unit="s",
        desc="ml-api-adapter's own handler-level view of transfer prepare/fulfil (separate metric family from the notification-handler's tx_transfer view below).",
    ),
    panel(
        "Notification handler — tx_transfer processing time p95",
        [
            target('histogram_quantile(0.95, sum by (le) (rate(moja_tx_transfer_bucket[$__rate_interval])))', "tx_transfer"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_tx_transfer_prepare_bucket[$__rate_interval])))', "tx_transfer prepare"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_tx_transfer_fulfil_bucket[$__rate_interval])))', "tx_transfer fulfil"),
        ],
        unit="s",
    ),
    panel(
        "Notification event — processing time p95, by stage",
        [
            target('histogram_quantile(0.95, sum by (le) (rate(moja_notification_event_bucket[$__rate_interval])))', "event (total)"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_notification_event_delivery_bucket[$__rate_interval])))', "delivery (to DFSP)"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_notification_event_getEndpoint_bucket[$__rate_interval])))', "getEndpoint"),
            target('histogram_quantile(0.95, sum by (le) (rate(moja_notification_event_process_msg_bucket[$__rate_interval])))', "process_msg"),
        ],
        unit="s",
        desc="Breakdown of notification (callback) processing — delivery is the actual outbound HTTP call to the DFSP, usually the largest share.",
    ),
    panel(
        "Throughput /sec — by service",
        [
            target('sum by (serviceName) (rate(moja_ml_transfer_prepare_count[$__rate_interval]))', "{{serviceName}} prepare"),
            target('sum by (serviceName) (rate(moja_ml_transfer_fulfil_count[$__rate_interval]))', "{{serviceName}} fulfil"),
            target('sum by (serviceName) (rate(moja_notification_event_delivery_count[$__rate_interval]))', "{{serviceName}} notif delivery"),
        ],
        unit="ops",
    ),
    panel(
        "Notification delivery errors (non-200 or success=false)",
        [
            target('sum by (status) (rate(moja_notification_event_delivery_count{status!="200"}[$__rate_interval]))', "status={{status}}"),
            target('sum(rate(moja_ml_transfer_fulfil_error_count[$__rate_interval]))', "fulfil errors"),
        ],
        unit="ops",
    ),
    panel(
        "Event loop lag (p99) by service",
        [target('moja_nodejs_eventloop_lag_p99_seconds{serviceName=~"ml-.*"}', "{{serviceName}} - {{pod}}")],
        unit="s",
    ),
]
ml_panels = expand_with_p99(ml_panels)
write("ml-api-adapter-v2.json", dashboard(
    "Mojaloop - ML-API Adapter", "ml-api-adapter-v2", ml_panels,
    ["ml-api-adapter", "latency", "whitepaper"],
))

# ---------------------------------------------------------------------------
# 8. MySQL Overview (v2) - modern mysqld_exporter (MySQL 8/9, no query cache)
# ---------------------------------------------------------------------------
mysql_panels = [
    panel(
        "Query throughput by command",
        [target('sum by (command) (rate(mysql_global_status_commands_total{command=~"select|insert|update|delete|begin|commit|insert_select"}[$__rate_interval]))', "{{command}}")],
        unit="ops",
        desc="Read/write mix, straight from MySQL's own command counters — should track the transfer prepare/fulfil rate almost exactly (each transfer = ~1 select + 1 insert/update + begin + commit).",
        stack=True,
    ),
    panel(
        "Row access pattern (handler operations)",
        [target('sum by (handler) (rate(mysql_global_status_handlers_total{handler=~"read_key|read_next|read_prev|read_rnd_next|write|update|commit"}[$__rate_interval]))', "{{handler}}")],
        unit="ops",
        desc="handler_read_key = index lookups (good). handler_read_rnd_next = full table/range scans without an index (watch this relative to read_key — a rising ratio means queries are scanning instead of seeking, usually a missing index or a query planner regression).",
    ),
    panel(
        "InnoDB redo log activity (durability cost)",
        [
            target('rate(mysql_global_status_innodb_log_writes[$__rate_interval])', "log writes/s"),
            target('rate(mysql_global_status_innodb_os_log_fsyncs[$__rate_interval])', "log fsyncs/s"),
        ],
        unit="ops",
        desc="Direct evidence of the innodb_flush_log_at_trx_commit=2 / sync_binlog=0 tuning this campaign relies on for throughput: log writes happen every commit, but OS fsyncs are decoupled (roughly once/sec) instead of once per commit — this ratio is WHY the relaxed durability setting buys throughput, and the actual risk window (up to ~1s of commits) if the broker crashes.",
    ),
    panel(
        "InnoDB physical disk I/O",
        [
            target('rate(mysql_global_status_innodb_data_reads[$__rate_interval])', "reads/s"),
            target('rate(mysql_global_status_innodb_data_writes[$__rate_interval])', "writes/s"),
            target('rate(mysql_global_status_innodb_data_fsyncs[$__rate_interval])', "fsyncs/s"),
        ],
        unit="ops",
        desc="Actual physical disk I/O (distinct from buffer-pool logical reads below) — reads/s should stay low if the working set fits in the buffer pool.",
    ),
    panel(
        "InnoDB buffer pool — hit ratio (%) and composition",
        [
            target(
                '100 * (1 - (rate(mysql_global_status_innodb_buffer_pool_reads[$__rate_interval]) '
                '/ rate(mysql_global_status_innodb_buffer_pool_read_requests[$__rate_interval])))',
                "hit ratio %",
            ),
        ],
        unit="percent",
        desc="Share of InnoDB reads served from the buffer pool vs disk. Low values mean the buffer pool is undersized for the working set.",
    ),
    panel(
        "InnoDB buffer pool pages by state",
        [
            target('mysql_global_status_buffer_pool_pages{state="data"}', "data"),
            target('mysql_global_status_buffer_pool_pages{state="free"}', "free"),
            target('mysql_global_status_buffer_pool_dirty_pages', "dirty"),
        ],
        unit="short",
        desc="'free' trending toward zero means the buffer pool is fully utilized (expected under load); 'dirty' pages awaiting flush to disk — a large sustained dirty count under these ephemeral-storage/eviction-prone nodes is worth watching.",
    ),
    panel(
        "Row lock waits / current waits",
        [
            target('rate(mysql_global_status_innodb_row_lock_waits[$__rate_interval])', "lock waits/s"),
            target('mysql_global_status_innodb_row_lock_current_waits', "current waits (gauge)"),
        ],
        unit="short",
    ),
    panel(
        "Temp tables — memory vs disk",
        [
            target('rate(mysql_global_status_created_tmp_tables[$__rate_interval])', "tmp tables (memory)/s"),
            target('rate(mysql_global_status_created_tmp_disk_tables[$__rate_interval])', "tmp tables (DISK)/s"),
        ],
        unit="ops",
        desc="Disk-based temp tables (sorts/joins that spilled past tmp_table_size) are a real performance red flag — should be at or near zero for this workload's simple queries.",
        thresholds=[{"color": "green", "value": None}, {"color": "red", "value": 1}],
    ),
    panel(
        "Table open cache efficiency",
        [
            target('rate(mysql_global_status_table_open_cache_hits[$__rate_interval])', "hits/s"),
            target('rate(mysql_global_status_table_open_cache_misses[$__rate_interval])', "misses/s"),
        ],
        unit="ops",
    ),
    panel(
        "Threads connected / running",
        [
            target('mysql_global_status_threads_connected', "connected"),
            target('mysql_global_status_threads_running', "running"),
        ],
        unit="short",
    ),
    panel(
        "Slow queries",
        [target('rate(mysql_global_status_slow_queries[$__rate_interval])', "slow queries/s")],
        unit="ops",
        thresholds=[{"color": "green", "value": None}, {"color": "red", "value": 1}],
    ),
    panel(
        "Connection errors / aborted connects",
        [
            target('rate(mysql_global_status_connection_errors_total[$__rate_interval])', "connection errors/s"),
            target('rate(mysql_global_status_aborted_connects[$__rate_interval])', "aborted connects/s"),
        ],
        unit="ops",
    ),
]
write("mysql-overview-v2.json", dashboard(
    "MySQL Overview", "mysql-overview-v2", mysql_panels,
    ["mysql", "datastore", "whitepaper"],
))

# ---------------------------------------------------------------------------
# 9. Kafka (validity-gate topics)
# ---------------------------------------------------------------------------
GATE_TOPICS = "topic-transfer-prepare|topic-transfer-fulfil|topic-notification-event|topic-transfer-position-batch|topic-quotes-post"
kafka_panels = [
    panel(
        "Consumer lag by topic — validity-gate topics",
        [target(f'sum by (consumergroup, topic) (kafka_consumergroup_lag{{topic=~"{GATE_TOPICS}", consumergroup!="cs-group-centralsettlement-handler-rules-notification-event"}})', "{{consumergroup}} ({{topic}})")],
        unit="short",
        desc="The topics steady-state.sh checks for the pass/fail validity gate (fulfil/prepare=1.0, notif/prepare=2.0). Rising lag on any of these is the leading indicator of backpressure/collapse — this was the dominant failure signature across every prior investigation in this campaign.",
    ),
    panel(
        "Message rate by topic — validity-gate topics",
        [target(f'clamp_min(sum by (topic) (rate(kafka_topic_partition_current_offset{{topic=~"{GATE_TOPICS}"}}[$__rate_interval])), 0)', "{{topic}}")],
        unit="ops",
        desc="Should hold flat at the target rate (500/s prepare+fulfil, 1000/s notification, 500/s quotes-post at 500 TPS) — a topic falling below target while others hold steady is the first sign of a stuck consumer group.",
    ),
    panel(
        "Partition count by topic — validity-gate topics",
        [target(f'sum by (topic) (kafka_topic_partitions{{topic=~"{GATE_TOPICS}"}})', "{{topic}}")],
        unit="short",
        desc="Direct catch for this campaign's recurring landmine: auto.create.topics.enable + ephemeral storage means ANY kafka restart can silently recreate a topic at 1 partition, stranding all-but-one consumer replica. A sudden drop in any topic's line is that exact failure — not a query problem, a real broker-state problem.",
    ),
    panel(
        "Consumer group members by group",
        [target('sum by (consumergroup) (kafka_consumergroup_members{consumergroup=~"cl-group-transfer-prepare|cl-group-transfer-fulfil|cl-group-transfer-position-batch|ml-group-notification-event"})', "{{consumergroup}}")],
        unit="short",
        desc="Consumer replica count per group actively registered with the broker — a drop here (without a corresponding deploy scale-down) means pods are failing to join/rejoin the group, the other half of the auto-create-at-1-partition failure mode.",
    ),
    panel(
        "Broker log size by topic — validity-gate topics",
        [target(f'sum by (topic) (kafka_log_log_size{{topic=~"{GATE_TOPICS}"}})', "{{topic}}")],
        unit="bytes",
        desc="Direct visibility into the root cause of the 06-30 ephemeral-storage eviction incident: unbounded segment growth (segment.bytes/segment.ms too loose relative to retention) grows this without bound until kubelet evicts the pod at the ephemeral-storage limit. Should plateau, not climb indefinitely.",
    ),
    panel(
        "Broker throughput — bytes in/out per sec",
        [
            target('sum(rate(kafka_server_brokertopicmetrics_total_bytesinpersec_count[$__rate_interval]))', "bytes in/s"),
            target('sum(rate(kafka_server_brokertopicmetrics_total_bytesoutpersec_count[$__rate_interval]))', "bytes out/s"),
        ],
        unit="Bps",
    ),
    panel(
        "Broker disk I/O (OS-level, from JMX)",
        [
            target('sum(rate(kafka_server_kafkaserver_total_linux_disk_read_bytes_value[$__rate_interval]))', "disk read/s"),
            target('sum(rate(kafka_server_kafkaserver_total_linux_disk_write_bytes_value[$__rate_interval]))', "disk write/s"),
        ],
        unit="Bps",
    ),
    panel(
        "Network processor idle (%) — broker saturation",
        [target('100 * avg(kafka_network_socketserver_networkprocessoravgidlepercent_value)', "network processor idle %")],
        unit="percent",
        desc="Fraction of time the broker's network I/O threads are idle. Falling toward 0 means the network layer itself is becoming the bottleneck, not just downstream processing.",
    ),
    panel(
        "Purgatory size — produce / fetch (broker-side queueing)",
        [
            target('sum(kafka_server_delayedoperationpurgatory_purgatorysize_produce_value)', "produce purgatory"),
            target('sum(kafka_server_delayedoperationpurgatory_purgatorysize_fetch_value)', "fetch purgatory"),
        ],
        unit="short",
        desc="Requests parked waiting on acks/data (e.g. acks=all waiting for replication, or long-poll fetches waiting for new messages). Fetch purgatory naturally holds some long-polling consumers even at idle; a sustained climb in produce purgatory is real backpressure.",
    ),
    panel(
        "Broker request rate by type",
        [target('sum by (request) (rate(kafka_network_requestmetrics_requestspersec_count[$__rate_interval]))', "{{request}}")],
        unit="reqps",
    ),
    panel(
        "Failed produce / fetch requests per sec",
        [
            target('sum(rate(kafka_server_brokertopicmetrics_total_failedproducerequestspersec_count[$__rate_interval]))', "failed produce/s"),
            target('sum(rate(kafka_server_brokertopicmetrics_total_failedfetchrequestspersec_count[$__rate_interval]))', "failed fetch/s"),
        ],
        unit="ops",
        thresholds=[{"color": "green", "value": None}, {"color": "red", "value": 0.1}],
    ),
    panel(
        "Replication health — under-replicated partitions, ISR shrink/expand",
        [
            target('sum(kafka_server_replicamanager_total_underreplicatedpartitions_value)', "under-replicated partitions"),
            target('sum(rate(kafka_server_replicamanager_total_isrshrinkspersec_count[$__rate_interval]))', "ISR shrinks/s"),
            target('sum(rate(kafka_server_replicamanager_total_isrexpandspersec_count[$__rate_interval]))', "ISR expands/s"),
        ],
        unit="short",
        desc="Should be flat zero in steady state. Non-zero ISR churn or any under-replicated partitions indicates broker instability (e.g. the ephemeral-storage eviction / OOM-restart incidents from earlier in this campaign).",
    ),
    panel(
        "Broker health — active controller, offline partitions, global topic/partition count",
        [
            target('sum(kafka_controller_kafkacontroller_activecontrollercount_value)', "active controllers (should be 1)"),
            target('sum(kafka_controller_kafkacontroller_offlinepartitionscount_value)', "offline partitions (should be 0)"),
            target('sum(kafka_controller_kafkacontroller_globaltopiccount_value)', "global topic count"),
            target('sum(kafka_controller_kafkacontroller_globalpartitioncount_value)', "global partition count"),
        ],
        unit="short",
        desc="Global partition count dropping unexpectedly (without a deliberate topic change) is cluster-wide confirmation of the auto-create-at-1-partition landmine, independent of the per-topic panel above.",
    ),
]
write("kafka-overview.json", dashboard(
    "Kafka - Whitepaper Overview", "kafka-whitepaper-overview", kafka_panels,
    ["kafka", "messaging", "whitepaper"],
))

# ---------------------------------------------------------------------------
# 10. FSP / DFSP Simulator — Capacity
# ---------------------------------------------------------------------------
# DFSP-side metrics arrive via each FSP's own Prometheus agent remote_write
# (the dfsp_monitoring role) — node-exporter + kubelet-cadvisor only, tagged
# with a `cluster` label (fsp201..fsp208) and a plain `node` label (no
# node_uname_info join needed, unlike the switch side). No app-level
# (moja_process_*, sdk-scheme-adapter) metrics are collected — confirmed
# absent live. Each FSP runs 3 components: scheme-adapter (sdk-scheme-adapter),
# backend (mojaloop-simulator), cache (redis for the scheme-adapter).
fsp_panels = [
    panel(
        "Node CPU utilisation % per FSP node",
        [target('100 * (1 - avg by (cluster) (rate(node_cpu_seconds_total{cluster=~"fsp.*", mode="idle"}[$__rate_interval])))', "{{cluster}}")],
        unit="percent",
        desc="One line per FSP node (fsp201-208). No node_uname_info join available on this side — the cluster label IS the node identifier.",
    ),
    panel(
        "Node memory utilisation % per FSP node",
        [target('100 * (1 - (node_memory_MemAvailable_bytes{cluster=~"fsp.*"} / node_memory_MemTotal_bytes{cluster=~"fsp.*"}))', "{{cluster}}")],
        unit="percent",
    ),
    panel(
        "CPU usage by FSP (cores) — scheme-adapter + backend + cache",
        [target('sum by (cluster) (rate(container_cpu_usage_seconds_total{namespace="dfsps", image!="", image!~".*pause.*"}[$__rate_interval]))', "{{cluster}}")],
        unit="short",
        desc="All 3 per-FSP components (sdk-scheme-adapter, mojaloop-simulator backend, redis cache) summed per FSP — should track the k6 FSP-pair traffic weights (fsp201/202 carry the bulk of the load, so expect them highest).",
    ),
    panel(
        "Memory usage by FSP — scheme-adapter + backend + cache",
        [target('sum by (cluster) (container_memory_working_set_bytes{namespace="dfsps", image!="", image!~".*pause.*"})', "{{cluster}}")],
        unit="bytes",
    ),
    panel(
        "CPU usage by FSP + component",
        [target('sum by (cluster, pod) (rate(container_cpu_usage_seconds_total{namespace="dfsps", image!="", image!~".*pause.*"}[$__rate_interval]))', "{{cluster}} - {{pod}}")],
        unit="short",
        desc="Per-pod breakdown (scheme-adapter vs backend vs cache) — identifies which DFSP-side component actually carries the CPU cost.",
    ),
]
write("fsp-capacity.json", dashboard(
    "FSP / DFSP Simulator — Capacity", "fsp-capacity", fsp_panels,
    ["fsp", "dfsp", "capacity", "whitepaper"],
))

print("done: central-ledger, als, quoting, ml-adapter, mysql, kafka, fsp")
