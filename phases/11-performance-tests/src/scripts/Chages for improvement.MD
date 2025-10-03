## Mysql Changes
### Increase the max_connections on mysql
```
Increase the resources to 3 cpu and 3gb memory
mysql -uroot -p"$MYSQL_ROOT_PASSWORD"

mysql> SHOW VARIABLES LIKE 'max_connections';
+-----------------+-------+
| Variable_name   | Value |
+-----------------+-------+
| max_connections | 151   |
+-----------------+-------+
1 row in set (0.008 sec)

mysql> SET GLOBAL max_connections = 2000;
Query OK, 0 rows affected (0.000 sec)

mysql> SHOW VARIABLES LIKE 'max_connections';
+-----------------+-------+
| Variable_name   | Value |
+-----------------+-------+
| max_connections | 2000  |
+-----------------+-------+
```
### increase resources
```
          resources:
            limits:
              cpu: '4'
              ephemeral-storage: 15Gi
              memory: 4Gi
            requests:
              cpu: '2'
              ephemeral-storage: 5Gi
              memory: 2Gi
```

## KFKA
### resources
```
          resources:
            limits:
              cpu: '3'
              ephemeral-storage: 15Gi
              memory: 4Gi
            requests:
              cpu: '1'
              ephemeral-storage: 5Gi
              memory: 2Gi
```
### partitions

```
    kafka-topics.sh --alter --topic topic-quotes-post --partitions 12 --bootstrap-server kafka:9092
    kafka-topics.sh --alter --topic topic-quotes-put --partitions 12 --bootstrap-server kafka:9092
    kafka-topics.sh --alter --topic topic-transfer-prepare --partitions 12 --bootstrap-server kafka:9092
    kafka-topics.sh --alter --topic topic-transfer-fulfil --partitions 12 --bootstrap-server kafka:9092
    kafka-topics.sh --alter --topic topic-transfer-position-batch --partitions 12 --bootstrap-server kafka:9092
    kafka-topics.sh --alter --topic topic-notification-event --partitions 24 --bootstrap-server kafka:9092
```



## Service replicas

➜ k get deploy -n mojaloop                
NAME                                                READY   UP-TO-DATE   AVAILABLE   AGE
moja-account-lookup-service                         7/16    16           7           13d
moja-account-lookup-service-admin                   1/1     1            1           13d
moja-als-msisdn-oracle                              4/4     4            4           13d
moja-centralledger-handler-admin-transfer           1/1     1            1           13d
moja-centralledger-handler-timeout                  1/1     1            1           13d
moja-centralledger-handler-transfer-fulfil          12/12   12           12          13d
moja-centralledger-handler-transfer-get             1/1     1            1           13d
moja-centralledger-handler-transfer-position        1/1     1            1           13d
moja-centralledger-handler-transfer-prepare         12/12   12           12          13d
moja-centralledger-service                          4/4     4            4           13d
moja-centralsettlement-handler-deferredsettlement   1/1     1            1           13d
moja-centralsettlement-handler-rules                0/0     0            0           13d
moja-centralsettlement-service                      1/1     1            1           13d
moja-handler-pos-batch                              12/12   12           12          13d
moja-ml-api-adapter-handler-notification            24/24   24           24          13d
moja-ml-api-adapter-service                         8/8     8            8           13d
moja-ml-testing-toolkit-frontend                    1/1     1            1           13d
moja-quoting-service                                8/8     8            8           13d
moja-quoting-service-handler                        12/12   12           12          13d





## Account lookup service

1. readiness and liveness probe = changed timeout and frequency to 5/60s
2. added resources
```
          resources:
            requests:
              cpu: "500m"
              memory: "512Mi"
            limits:
              cpu: "1000m"
              memory: "1.5Gi"

```
```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: moja-account-lookup-service
  namespace: mojaloop
  uid: c5c88d28-1780-42e4-86c7-7c8057696237
  resourceVersion: '6608982'
  generation: 21
  creationTimestamp: '2025-09-12T09:59:55Z'
  labels:
    app.kubernetes.io/instance: moja
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/name: account-lookup-service
    app.kubernetes.io/version: 15.3.0
    helm.sh/chart: account-lookup-service-15.3.0
  annotations:
    deployment.kubernetes.io/revision: '1'
    meta.helm.sh/release-name: moja
    meta.helm.sh/release-namespace: mojaloop
  selfLink: /apis/apps/v1/namespaces/mojaloop/deployments/moja-account-lookup-service
status:
  observedGeneration: 21
  replicas: 16
  updatedReplicas: 16
  readyReplicas: 16
  availableReplicas: 16
  conditions:
    - type: Progressing
      status: 'True'
      lastUpdateTime: '2025-09-12T10:01:11Z'
      lastTransitionTime: '2025-09-12T09:59:55Z'
      reason: NewReplicaSetAvailable
      message: >-
        ReplicaSet "moja-account-lookup-service-7c8576d59b" has successfully
        progressed.
    - type: Available
      status: 'True'
      lastUpdateTime: '2025-09-26T06:16:12Z'
      lastTransitionTime: '2025-09-26T06:16:12Z'
      reason: MinimumReplicasAvailable
      message: Deployment has minimum availability.
spec:
  replicas: 16
  selector:
    matchLabels:
      app.kubernetes.io/instance: moja
      app.kubernetes.io/name: account-lookup-service
  template:
    metadata:
      creationTimestamp: null
      labels:
        app.kubernetes.io/instance: moja
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/name: account-lookup-service
        app.kubernetes.io/version: 15.3.0
        helm.sh/chart: account-lookup-service-15.3.0
      annotations:
        checksum/config: a9bc37263cf653f077a33930783ecca2a214e284624edaec96ce81695f03215c
        checksum/secret-jws: f3972866abe6fde0df0b86e0f61f2e10c69ca2188085d7bbb11c22fe1b182b54
        prometheus.io/port: '4002'
        prometheus.io/scrape: 'true'
    spec:
      volumes:
        - name: moja-account-lookup-service-config-volume
          configMap:
            name: moja-account-lookup-service-config
            items:
              - key: default.json
                path: default.json
              - key: knexfile.js
                path: knexfile.js
            defaultMode: 420
        - name: jws-signing-key
          secret:
            secretName: moja-account-lookup-service-jws-signing-key
            defaultMode: 420
      initContainers:
        - name: wait-for-mysql
          image: mysql:9.0.1
          command:
            - sh
            - '-c'
            - >
              until result=$(mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER}
              --password=${DB_PASSWORD} ${DB_DATABASE} -ss -N -e 'select
              is_locked from migration_lock;') && eval 'echo is_locked=$result'
              && if [ -z $result ]; then false; fi && if [ $result -ne 0 ]; then
              false; fi;

              do
                echo --------------------;
                echo Waiting for MySQL...;
                sleep 2;
              done;

              echo ====================;

              echo MySQL ok!;
          env:
            - name: DB_HOST
              value: mysqldb
            - name: DB_PORT
              value: '3306'
            - name: DB_USER
              value: account_lookup
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysqldb
                  key: mysql-password
            - name: DB_DATABASE
              value: account_lookup
          resources: {}
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
          imagePullPolicy: IfNotPresent
      containers:
        - name: account-lookup-service
          image: mojaloop/account-lookup-service:v17.12.2
          command:
            - node
            - src/index.js
            - server
            - '--api'
          ports:
            - name: http
              containerPort: 4002
              protocol: TCP
          env:
            - name: ALS_DATABASE__PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysqldb
                  key: mysql-password
            - name: LOG_LEVEL
              value: info
            - name: CSL_LOG_TRANSPORT
              value: console
            - name: EVENT_SDK_LOG_FILTER
              value: audit:*, log:warn, log:error
            - name: EVENT_SDK_LOG_METADATA_ONLY
              value: 'false'
            - name: EVENT_SDK_VENDOR_PREFIX
              value: mojaloop
            - name: EVENT_SDK_TRACESTATE_HEADER_ENABLED
              value: 'true'
            - name: EVENT_SDK_ASYNC_OVERRIDE_EVENTS
              value: log,trace
            - name: EVENT_SDK_TRACEID_PER_VENDOR
              value: 'false'
          resources:
            requests:
              cpu: "500m"
              memory: "512Mi"
            limits:
              cpu: "1000m"
              memory: "1.5Gi"
          volumeMounts:
            - name: moja-account-lookup-service-config-volume
              mountPath: /opt/app/config
            - name: jws-signing-key
              mountPath: /opt/app/secrets
          livenessProbe:
            httpGet:
              path: /health
              port: 4002
              scheme: HTTP
            initialDelaySeconds: 60
            timeoutSeconds: 5
            periodSeconds: 60
            successThreshold: 1
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /health
              port: 4002
              scheme: HTTP
            initialDelaySeconds: 60
            timeoutSeconds: 5
            periodSeconds: 60
            successThreshold: 1
            failureThreshold: 3
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
          imagePullPolicy: IfNotPresent
          securityContext:
            runAsUser: 1001
            readOnlyRootFilesystem: true
      restartPolicy: Always
      terminationGracePeriodSeconds: 30
      dnsPolicy: ClusterFirst
      securityContext: {}
      schedulerName: default-scheduler
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: account-lookup-service
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: account-lookup-service
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 25%
      maxSurge: 25%
  revisionHistoryLimit: 10
  progressDeadlineSeconds: 600
```

## coredns
scaled up the replicas to 4 



## ml-api-adapter-notification handler
### replicas = 24
### kafka config

```            "CONSUMER": {
                "NOTIFICATION": {
                    "EVENT": {
                        "config": {
                            "options": {
                                "mode": 2,
                                "batchSize": 50,
                                "recursiveTimeout": 100,
                                "messageCharset": "utf8",
                                "messageAsJSON": true,
                                "sync": true,
                                "consumeTimeout": 10
                            },
                            "rdkafkaConf": {
                                "client.id": "ml-con-notification-event",
                                "group.id": "ml-group-notification-event",
                                "metadata.broker.list": "kafka:9092",
                                "socket.keepalive.enable": true,
                                "allow.auto.create.topics": true
                            },
                            "topicConf": {
                                "auto.offset.reset": "earliest"
                            }
                        }
                    }
                }
```                

## Quoting Service handler

### change the cache timeout of participant cache

```
      "CACHE": {
        "ENUM_DATA_EXPIRES_IN_MS": 4.17e+06,
        "PARTICIPANT_DATA_EXPIRES_IN_MS": 600
      },
```

### kafka config
```
        "CONSUMER":{
          "QUOTE":{
            "POST":{
              "topic":"topic-quotes-post",
              "config":{
                "options":{
                  "mode":2,
                  "batchSize":50, <----
                  "pollFrequency":10,
                  "recursiveTimeout":100,
                  "messageCharset":"utf8",
                  "messageAsJSON":true,
                  "sync":true,
                  "consumeTimeout":10 <----
                },
                "rdkafkaConf":{
                  "client.id":"quotes-handler-post_c_${POD_NAME}",
                  "group.id":"group-quotes-handler-post",
                  "metadata.broker.list": "kafka:9092",
                  "socket.keepalive.enable":true,
                  "enable.auto.commit": true,
                  "allow.auto.create.topics":true
                },
                "topicConf":{
                  "auto.offset.reset":"earliest"
                }
              }
            },
            "PUT":{
              "topic":"topic-quotes-put",
              "config":{
                "options":{
                  "mode":2,
                  "batchSize":50, <----
                  "pollFrequency":10,
                  "recursiveTimeout":100,
                  "messageCharset":"utf8",
                  "messageAsJSON":true,
                  "sync":true,
                  "consumeTimeout":10 <----
                },
                "rdkafkaConf":{
                  "client.id":"quotes-handler-put_c_${POD_NAME}",
                  "group.id":"group-quotes-handler-put",
                  "metadata.broker.list": "kafka:9092",
                  "enable.auto.commit": true,
                  "socket.keepalive.enable":true,
                  "allow.auto.create.topics":true
                },
                "topicConf":{
                  "auto.offset.reset":"earliest"
                }
              }
            }
          },

```


## Position Batch
### KAFKA config
```
                    "POSITION_BATCH": {
                        "config": {
                          "options": {
                            "mode": 2,
                            "batchSize": 100,
                            "pollFrequency": 10,
                            "recursiveTimeout": 100,
                            "messageCharset": "utf8",
                            "messageAsJSON": true,
                            "sync": true,
                            "consumeTimeout": 10
                          },
                          "rdkafkaConf": {
                            "client.id": "cl-con-transfer-position-batch",
                            "group.id": "cl-group-transfer-position-batch",
                            "metadata.broker.list": "kafka:9092",
                            "socket.keepalive.enable": true,
                            "allow.auto.create.topics": true,
                            "partition.assignment.strategy": "",
                            "enable.auto.commit": false
                          },
                          "topicConf": {
                            "auto.offset.reset": "earliest"
                          }
                        }
                    },

```                    

## Transfer prepare
### kafka config
```
                "TRANSFER": {
                    "PREPARE": {
                        "config": {
                            "options": {
                                "mode": 2,
                                "batchSize": 50, <----
                                "syncConcurrency": 50, <----
                                "syncSingleMessage": true, <----
                                "pollFrequency": 10,
                                "recursiveTimeout": 100,
                                "messageCharset": "utf8",
                                "messageAsJSON": true,
                                "sync": true,<----
                                "consumeTimeout": 10 
                            },
                            "rdkafkaConf": {
                                "client.id": "cl-con-transfer-prepare",
                                "group.id": "cl-group-transfer-prepare",
                                "metadata.broker.list": "kafka:9092",
                                "socket.keepalive.enable": true,
                                "allow.auto.create.topics": true
                            },
                            "topicConf": {
                                "auto.offset.reset": "earliest"
                            }
                        }
                    }
                }

```



## DFSPs
 8 replicas if sdk
 set below env variable
 PATCH_NOTIFICATION_GRACE_TIME_MS:0 
 use mojaloop/sdk-scheme-adapter:v24.12.0 image

 3 replicas of coredns