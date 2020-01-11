FROM alpine:3.11
RUN \
    apk add --no-cache \
    inkscape \
    ruby \
    ruby-rdoc \
    font-noto \
    msttcorefonts-installer
COPY . .
RUN \
    update-ms-fonts && \
    fc-cache -f
RUN \
    gem build inkmake.gemspec && \
    gem install inkmake
ENTRYPOINT ["inkmake"]
