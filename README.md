# streamer
- watches a directory
- streams the oldest video
- streams a idle loop if no video is found
- stops streaming after `$IDLE_TIMEOUT` seconds with no new video
- resumes stream when new video is found

This requires all videos to have the same codecs, resolution etc.

## Usage
```
INPUT_DIR=input/ ARCHIVE_DIR=archive/ IDLE_VIDEO=idle.mp4 OUTPUT_URL='rtmp://localhost:1935/live/test' ./streamer.sh
```

Or in Docker:
```
docker build -t streamer .
docker run --rm -v $PWD/input:/input -v $PWD/archive:/archive -v $PWD/idle.mp4:/assets/idle.mp4 \
    -e OUTPUT_URL='rtmp://localhost:1935/live/test' streamer
```


