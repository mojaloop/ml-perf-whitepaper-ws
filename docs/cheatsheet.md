# Operations Cheatsheet

Quick reference for ad-hoc operations on the perf lab. None of these
are required for `make` targets — those are all automated. This is
purely for poking at a running cluster.

## Cluster access

All clusters are private. Open a SOCKS5 tunnel through the bastion
once per shell:

```bash
ssh -D 1080 perf-jump-host -N &
export HTTPS_PROXY=socks5://127.0.0.1:1080
```

Then point `KUBECONFIG` at the cluster you want:

```bash
export KUBECONFIG=infrastructure/provisioning/artifacts/kubeconfigs/kubeconfig-mojaloop-switch.yaml
# or kubeconfig-fsp201.yaml ... kubeconfig-fsp208.yaml ... kubeconfig-k6.yaml
```

## Scaling app handlers (switch)

Burst all handlers down (e.g. before a config change), then back up.
Replica counts mirror a 500 TPS profile — adjust per scenario.

```bash
# down
kubectl -n mojaloop scale deployment moja-centralledger-handler-transfer-fulfil       --replicas=0
kubectl -n mojaloop scale deployment moja-centralledger-handler-transfer-prepare      --replicas=0
kubectl -n mojaloop scale deployment moja-handler-pos-batch                            --replicas=0
kubectl -n mojaloop scale deployment moja-ml-api-adapter-handler-notification          --replicas=0
kubectl -n mojaloop scale deployment moja-ml-api-adapter-service                       --replicas=0
kubectl -n mojaloop scale deployment moja-quoting-service                              --replicas=0
kubectl -n mojaloop scale deployment moja-quoting-service-handler                      --replicas=0

# up (500 TPS sizing)
kubectl -n mojaloop scale deployment moja-centralledger-handler-transfer-fulfil       --replicas=12
kubectl -n mojaloop scale deployment moja-centralledger-handler-transfer-prepare      --replicas=12
kubectl -n mojaloop scale deployment moja-handler-pos-batch                            --replicas=8
kubectl -n mojaloop scale deployment moja-ml-api-adapter-handler-notification          --replicas=18
kubectl -n mojaloop scale deployment moja-ml-api-adapter-service                       --replicas=12
kubectl -n mojaloop scale deployment moja-quoting-service                              --replicas=12
kubectl -n mojaloop scale deployment moja-quoting-service-handler                      --replicas=12
```

## Kafka

Partition counts MUST match the consumer replica count for that topic
(otherwise you cap throughput). Repartition by exec'ing into a Kafka
broker pod, then:

```bash
kafka-topics.sh --alter --topic topic-quotes-post              --partitions 12 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-quotes-put               --partitions 12 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-transfer-prepare         --partitions 12 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-transfer-fulfil          --partitions 12 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-transfer-position-batch  --partitions  8 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-notification-event       --partitions 18 --bootstrap-server kafka:9092
```

Inspect a topic:

```bash
kafka-topics.sh --describe --topic topic-notification-event       --bootstrap-server kafka:9092
kafka-topics.sh --describe --topic topic-quotes-post              --bootstrap-server kafka:9092
kafka-topics.sh --describe --topic topic-transfer-position-batch  --bootstrap-server kafka:9092
kafka-topics.sh --describe --topic topic-transfer-prepare         --bootstrap-server kafka:9092
```

Search a topic for a specific transferId / quoteId:

```bash
kafka-console-consumer.sh \
  --bootstrap-server kafka:9092 \
  --topic topic-notification-event \
  --from-beginning \
  --timeout-ms 120000 \
  --property print.timestamp=true \
  --property print.key=true \
  --property print.value=true \
| grep "<your-id-here>"
```

Search all partitions in parallel:

```bash
for i in $(seq 0 39); do
  echo "Searching partition $i..."
  kafka-console-consumer.sh \
    --bootstrap-server kafka:9092 \
    --topic topic-notification-event \
    --partition $i \
    --from-beginning \
    --timeout-ms 60000 \
  | grep "<your-id-here>" &
done
wait
```

Browse interactively with kafka-ui:

```bash
kubectl apply -f tools/kafka-debug-ui-pod.yaml
kubectl -n mojaloop port-forward pod/kafka-ui 8080:8080
# open http://localhost:8080
```

## curl from inside the cluster

For probing in-cluster services (especially with hostAliases injected
by the egress mTLS pattern):

```bash
kubectl apply -f tools/curl-pod.yaml -n k6-test
kubectl exec -it -n k6-test curl-k6-test -- sh
```

## mTLS sanity probes

Quick verification that egress mTLS is working from the switch to a
DFSP. Run from a switch-namespace pod that has the
`hostAliases-mtls.json` patch applied:

```bash
for i in 201 202 203 204 205 206 207 208; do
  printf 'fsp%s: HTTP=%s\n' $i \
    $(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 \
      http://sim-fsp${i}.local/sim/fsp${i}/inbound/anything)
done
# expect: HTTP=200 across the board
```

End-to-end smoke transfer (POST /transfers + acceptParty + acceptQuote
through the SDK adapter); driven by `tools/smoke-transfer.sh` once
moved over.
