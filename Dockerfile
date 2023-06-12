FROM debian:bookworm
# For some reason tail'ing the fifo doesn't work on the rootfs
# so we need a volume for this.

RUN apt-get -qy update && apt-get -qy install ffmpeg netcat-traditional awscli && \
    useradd -U -u 1000 user && \
    install -d -o user -g user -m 0755 /input /archive /assets /fifo

VOLUME /input
VOLUME /archive
VOLUME /fifo


ENV IDLE_VIDEO /assets/idle.mp4

ENV FIFO /fifo/stream

COPY streamer.sh /usr/bin/streamer.sh
COPY idle.mp4 /assets/idle.mp4

USER user

ENTRYPOINT [ "/usr/bin/streamer.sh" ]
