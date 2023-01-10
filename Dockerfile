FROM debian:buster

RUN apt-get -qy update && apt-get -qy install ffmpeg
COPY streamer.sh /usr/bin/streamer.sh

VOLUME /input
VOLUME /archive
VOLUME /assets

ENV INPUT_DIR /input
ENV ARCHIVE_DIR /archive
ENV IDLE_VIDEO /assets/idle.mp4

# For some reason tail'ing the fifo doesn't work on the rootfs
# so we need a volume for this.
VOLUME /fifo
ENV FIFO /fifo/stream

ENTRYPOINT [ "/usr/bin/streamer.sh" ]
