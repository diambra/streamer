#!/bin/bash
set -euo pipefail

# Check required env variables
for v in INPUT_DIR ARCHIVE_DIR IDLE_VIDEO OUTPUT_URL; do
    if [[ "${!v:-}" == "" ]]; then
        echo "Missing required env variable: $v"
        exit 1
    fi
done

if [[ "${FIFO:-}" == "" ]]; then
    fifo=$(mktemp -u) # Safe because mkfifo will fail if file already exists
else
    fifo="$FIFO"
fi

IDLE_TIMEOUT=${IDLE_TIMEOUT:-900}
SINCE_LAST_STREAMED=$(date +%s)
PIDFILE=$(mktemp)

rm -f "$fifo"
mkfifo "$fifo"

watch_dir() {
    local stream=1
    while true; do
        video=$(find "$INPUT_DIR" -type f -printf "%T@ %p\n" | sort -n | cut -d' ' -f2- | head -1)
        if [[ -n "$video" ]]; then
            stream=1
            echo "Found video: $video"
            ffmpeg -y -loglevel warning -re -i "$video" -vcodec copy -an -f mpegts "$fifo"
            mv "$video" "$ARCHIVE_DIR/"
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
            kill "$(cat "$PIDFILE")"
            continue
        fi

        ffmpeg -y -loglevel warning -re -i "$IDLE_VIDEO" -vcodec copy -an -f mpegts "$fifo"
    done
}

watch_dir | sed -u 's/^/watch_dir: /' &
WPID=$!
trap 'echo trapped signal, exiting...; kill $PID $WPID; exit 0' SIGTERM SIGINT

while true; do
    # Run in background so we can trap TERM/INT to kill watch_dir
    tail -c +1 -F "$fifo" | ffmpeg -loglevel warning -re -i - \
        -acodec copy -vcodec copy \
        -f flv -ac 2 -flvflags no_duration_filesize "$OUTPUT_URL" &
    PID=$!
    echo "$PID" > "$PIDFILE"
    wait $PID || true
done

kill $WPID
wait
