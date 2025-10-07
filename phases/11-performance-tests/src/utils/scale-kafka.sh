## Commands to partition kafka topics for performance testing. Shell into to kafka container and run these commands as needed

kafka-topics.sh --alter --topic topic-quotes-post --partitions 12 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-quotes-put --partitions 12 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-transfer-prepare --partitions 12 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-transfer-fulfil --partitions 12 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-transfer-position-batch --partitions 12 --bootstrap-server kafka:9092
kafka-topics.sh --alter --topic topic-notification-event --partitions 24 --bootstrap-server kafka:9092

#kafka-topics.sh --alter --topic topic-transfer-get --partitions 12 --bootstrap-server kafka:9092


kafka-topics.sh --describe --topic topic-notification-event --bootstrap-server kafka:9092
kafka-topics.sh --describe --topic topic-quotes-post --bootstrap-server kafka:9092
