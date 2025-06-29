# streamer
- watches a directory (a) or sqs queue (b)
- streams the oldest video, then a) move it to an archive directory or b) delete it from the queue
- streams a idle loop if no video is found
- stops streaming after `$IDLE_TIMEOUT` seconds with no new video
- resumes stream when new video is found

This requires all videos to have the same codecs, resolution etc.

## Usage
```
INPUT_DIR=input/ ARCHIVE_DIR=archive/ IDLE_VIDEO=idle.mp4 OUTPUT_URL='rtmp://live.twitch.tv/app/xx' ./streamer.sh
```

Or in Docker:
```
docker build -t streamer .
docker run --rm --net=host -v $PWD/input:/input -v $PWD/archive:/archive -v $PWD/idle.mp4:/assets/idle.mp4 \
    -e OUTPUT_URL='rtmp://live.twitch.tv/app/xx' -p 8080:8080 streamer
```

Using S3:
```
docker run --rm \
  --name streamer-aivsai \
  -e AWS_DEFAULT_REGION=us-west-2 \
  -e SQS_QUEUE="diambra-record-queue-aivsai" \
  -e OUTPUT_URL="rtmp://iad03.contribute.live-video.net/app/live_1302384669_LdZg5osesW2itAKcM4LKdk8gjOUYqM" \
  -e AUTH_TOKEN="$(cat ~/.diambra/admin-token)" \
  --mount type=bind,source=$HOME/.aws,target=/root/.aws,readonly \
  streamer
```

## Deploy
Deployment manifests are in [deploy](deploy/). They expect as secret `streamer` with a `output_url` key.
