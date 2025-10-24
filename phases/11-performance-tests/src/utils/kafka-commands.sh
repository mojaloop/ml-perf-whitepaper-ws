## Commands to partition kafka topics for performance testing. Shell into to kafka container and run these commands as needed

kafka-topics.sh --alter --topic topic-quotes-post --partitions 12 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-quotes-put --partitions 12 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-transfer-prepare --partitions 12 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-transfer-fulfil --partitions 12 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-transfer-position-batch --partitions 8 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-notification-event --partitions 18 --bootstrap-server kafka:9092


kafka-topics.sh --describe --topic topic-notification-event --bootstrap-server kafka:9092
kafka-topics.sh --describe --topic topic-quotes-post --bootstrap-server kafka:9092
kafka-topics.sh --describe --topic topic-transfer-position-batch --bootstrap-server kafka:9092
kafka-topics.sh --describe --topic topic-transfer-prepare --bootstrap-server kafka:9092


## Search for specific key in topic-notification-event
kafka-console-consumer.sh \
  --bootstrap-server kafka:9092 \
  --topic topic-notification-event \
  --from-beginning \
  --timeout-ms 120000 \
  --property print.timestamp=true \
  --property print.key=true \
  --property print.value=true \
| grep "0199E5F4487DC41C0F1F7A79DC"


## Searching all partitions for specific key in topic-notification-event
for i in $(seq 0 39); do
  echo "Searching partition $i..."
  kafka-console-consumer.sh \
    --bootstrap-server kafka:9092 \
    --topic topic-notification-event \
    --partition $i \
    --from-beginning \
    --timeout-ms 60000 \
  | grep "0199E61206F0471ABC1B85985F" &
done
wait