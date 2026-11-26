# TC-KAFKA-001 Kafka 生产消费

- 级别：P1
- 前置：Kafka Broker@h0:9092
- 关联：IT-KAFKA-001/002

## 步骤

```bash
docker exec bigtop_hostname0 bash -c "
  kafka-topics.sh --bootstrap-server bigtop-hostname0:9092 \
    --create --topic tc_t --partitions 1 --replication-factor 1 || true
  echo 'hello-kafka' | kafka-console-producer.sh \
    --bootstrap-server bigtop-hostname0:9092 --topic tc_t
  timeout 10 kafka-console-consumer.sh \
    --bootstrap-server bigtop-hostname0:9092 --topic tc_t --from-beginning --max-messages 1
  kafka-topics.sh --bootstrap-server bigtop-hostname0:9092 --delete --topic tc_t
"
```

## 期望

- 消费者输出 `hello-kafka`

## 结果

| 日期 | 结果 | 备注 |
|---|---|---|
| 2026-10-29 | ⏳ 待执行 | 9092 监听 |
