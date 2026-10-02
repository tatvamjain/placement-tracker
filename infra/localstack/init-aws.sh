#!/bin/bash
set -euo pipefail

MAX_RECEIVE_COUNT=5

create_topic() {
  awslocal sns create-topic --name "$1" --query TopicArn --output text
}

queue_arn() {
  local url
  url=$(awslocal sqs get-queue-url --queue-name "$1" --query QueueUrl --output text)
  awslocal sqs get-queue-attributes --queue-url "$url" \
    --attribute-names QueueArn --query Attributes.QueueArn --output text
}

create_queue_with_dlq() {
  local name=$1
  awslocal sqs create-queue --queue-name "${name}-dlq" >/dev/null
  local dlq_arn
  dlq_arn=$(queue_arn "${name}-dlq")
  awslocal sqs create-queue --queue-name "$name" \
    --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"${dlq_arn}\\\",\\\"maxReceiveCount\\\":\\\"${MAX_RECEIVE_COUNT}\\\"}\"}" >/dev/null
  queue_arn "$name"
}

subscribe() {
  awslocal sns subscribe --topic-arn "$1" --protocol sqs \
    --notification-endpoint "$2" \
    --attributes RawMessageDelivery=true >/dev/null
}

AUTH_TOPIC=$(create_topic auth-events)
PLACEMENT_TOPIC=$(create_topic placement-events)

PLACEMENT_FROM_AUTH=$(create_queue_with_dlq placement-from-auth)
subscribe "$AUTH_TOPIC" "$PLACEMENT_FROM_AUTH"

NOTIFY_FROM_AUTH=$(create_queue_with_dlq notification-from-auth)
subscribe "$AUTH_TOPIC" "$NOTIFY_FROM_AUTH"

NOTIFY_FROM_PLACEMENT=$(create_queue_with_dlq notification-from-placement)
subscribe "$PLACEMENT_TOPIC" "$NOTIFY_FROM_PLACEMENT"

echo "Event bus ready"