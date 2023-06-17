#!/bin/bash
set -euo pipefail

# Check required env variables
for v in IDLE_VIDEO OUTPUT_URL; do
    if [[ "${!v:-}" == "" ]]; then
        echo "Missing required env variable: $v"
        exit 1
    fi
done

if [[ -z "${INPUT_DIR:-}${SQS_QUEUE:-}" ]]; then
    echo "Must specify either INPUT_DIR or SQS_QUEUE"
    exit 1
fi

if [[ "${FIFO:-}" == "" ]]; then
    fifo=$(mktemp -u) # Safe because mkfifo will fail if file already exists
else
    fifo="$FIFO"
fi

IDLE_TIMEOUT=${IDLE_TIMEOUT:-900}
PATTERN=${PATTERN:-*.mp4}
SINCE_LAST_STREAMED=$(date +%s)
PIDFILE=$(mktemp)

METRICS=$(mktemp -d)
echo 0 > "$METRICS/errors"
echo 0 > "$METRICS/videos"
echo 0 > "$METRICS/streaming"

rm -f "$fifo"
mkfifo "$fifo"

watch_dir() {
    local stream=0
    while true; do
        local video=""
        local sqs_message
        local sqs_message_id
        if [[ -n "${INPUT_DIR:-}" ]]; then
            video=$(find "$INPUT_DIR" -type f -name "$PATTERN" -printf "%T@ %p\n"  | sort -n | cut -d' ' -f2- | head -1)
        else
            sqs_message=$(aws sqs receive-message --queue-url "$SQS_QUEUE" --max-number-of-messages 1)
            record=$(echo "$sqs_message" | jq -r '.Messages[0].Body')

            event_name=$(echo "$record" | jq -r '.Records[0].eventName')
            sqs_message_id=$(echo "$sqs_message" | jq -r '.Messages[0].ReceiptHandle')
            if [[ "$event_name" != ObjectCreated:* ]]; then
                echo "Ignoring event: $event_name with message id: $sqs_message_id"
            else
                bucket=$(echo "$record" | jq -r '.Records[0].s3.bucket.name')
                key=$(echo "$record" | jq -r '.Records[0].s3.object.key')
                video=$(aws s3 presign "s3://$bucket/$key" --expires-in 3600)
            fi
        fi
        if [[ -n "$video" ]]; then
            stream=1
            echo 1 > "$METRICS/streaming"
            echo "Found video: $video"
            inc "videos"
            while ! ffmpeg -y -loglevel warning -re -i "$video" -vcodec copy -f mpegts "$fifo"; do
                echo "Failed to stream video, retrying..."
                inc "errors"
                sleep 1
            done
            echo "Finished streaming video"
            if [[ -n "${INPUT_DIR:-}" ]]; then
                mv "$video" "$ARCHIVE_DIR/"
            else
                aws sqs delete-message --queue-url "$SQS_QUEUE" --receipt-handle "$sqs_message_id"
            fi
            echo "Marked video as streamed"
            SINCE_LAST_STREAMED=$(date +%s)
            continue
        fi

        if [[ "$stream" -eq 0 ]]; then
            sleep 1
            continue
        fi

        if [[ $(($(date +%s) - SINCE_LAST_STREAMED)) -gt $IDLE_TIMEOUT ]]; then
            echo "No videos found for $IDLE_TIMEOUT seconds, pausing stream"
            stream=0
            echo 0 > "$METRICS/streaming"
            kill "$(cat "$PIDFILE")"
            continue
        fi

        if ! ffmpeg -y -loglevel warning -re -i "$IDLE_VIDEO" -vcodec copy -f mpegts "$fifo"; then
            echo "Failed to stream idle video, retrying..."
            inc "$METRICS/errors"
            sleep 1
        fi
    done
}


inc() {
    local metric="$1"
    local file="$METRICS/$metric"
    local count
    count=$(cat "$file" || echo 0)
    echo $((count + 1)) > "$file"
}

metrics_server() {
    while true; do
        cat <<EOF | nc -l -p 8080 -q 0 | head -n 1
HTTP/1.1 200 OK
Content-Type: text/plain; version=0.0.4

# HELP streamer_errors_total Total number of errors
# TYPE streamer_errors_total counter
streamer_errors_total $(cat "$METRICS/errors")
# HELP streamer_videos_total Total number of videos streamed
# TYPE streamer_videos_total counter
streamer_videos_total $(cat "$METRICS/videos")
# HELP streamer_streaming Whether the streamer is currently streaming
# TYPE streamer_streaming gauge
streamer_streaming $(cat "$METRICS/streaming")
EOF
    done
}

stream() {
    local fifo="$1"
    local output="$2"

    while true; do
        if ! tail -c +1 -F "$fifo" | ffmpeg -loglevel warning -re -fflags +discardcorrupt -i - \
            -c:v copy -c:a aac \
            -f flv -ac 2 -flvflags no_duration_filesize "$output"; then
            echo "Stream failed"
        else
            echo "Stream exited unexpectedly, retrying..."
        fi
        inc "errors"
        sleep 1
    done
}

watch_dir 2>&1 | sed -u 's/^/watch_dir: /' &
WPID=$!

metrics_server 2>&1 | sed -u 's/^/metrics_server: /' &
MPID=$!

trap 'echo trapped signal, exiting...; kill "$PID" "$WPID" "$MPID"; rm "$PIDFILE" "$METRICS"; exit 0' SIGTERM SIGINT

while true; do
    # Run in background so we can trap TERM/INT to kill watch_dir
    stream "$fifo" "$OUTPUT_URL" 2>&1 | sed -u 's/^/stream: /' &
    PID=$!
    echo "$PID" > "$PIDFILE"
    wait $PID || true
done

kill $WPID
wait
