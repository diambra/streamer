#!/bin/bash
set -euo pipefail

POST_PROCESS_DIR=${POST_PROCESS_DIR:-/tmp/hooks.d}


while true; do
    if ! sqs_message=$(aws sqs receive-message --queue-url "$SQS_QUEUE" --max-number-of-messages 1); then
        echo "Failed to receive message from SQS, retrying..."
        sleep 1
        continue
    fi

    if [[ -z "$sqs_message" ]]; then
        echo "No messages in SQS queue, sleeping..."
        sleep 1
        continue
    fi

    record=$(echo "$sqs_message" | jq -r '.Messages[0].Body')

    event_name=$(echo "$record" | jq -r '.Records[0].eventName')
    sqs_message_id=$(echo "$sqs_message" | jq -r '.Messages[0].ReceiptHandle')
    if [[ "$event_name" != ObjectCreated:* ]]; then
        echo "Ignoring event: $event_name with message id: $sqs_message_id"
        sleep 1
        continue
    fi

    bucket=$(echo "$record" | jq -r '.Records[0].s3.bucket.name')
    key=$(echo "$record" | jq -r '.Records[0].s3.object.key')
    #video=$(aws s3 presign "s3://$bucket/$key" --expires-in 3600)
    tmpfile=$(mktemp /tmp/videoXXXX)
    aws s3 cp "s3://$bucket/$key" "$tmpfile"
    video="$tmpfile"

    echo "Streaming video: $video"
    ffmpeg -loglevel warning -re -i "$video" \
            -fflags +discardcorrupt -analyzeduration 10000000 -probesize 10000000 \
            -c:v libx264 -c:a aac \
            -preset veryfast -tune zerolatency  -f flv -vf "scale=1920:1080:force_original_aspect_ratio=decrease" \
            -f flv -ac 2 -flvflags no_duration_filesize "$OUTPUT_URL"
    rm -f "$tmpfile"
    echo "Finished streaming video"
    aws sqs delete-message --queue-url "$SQS_QUEUE" --receipt-handle "$sqs_message_id"
    if ! run-parts "$POST_PROCESS_DIR" -a "$key"; then
        echo "Failed to run post-processing script"
    fi
done
