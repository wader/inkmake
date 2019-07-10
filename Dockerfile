FROM alpine:3.10
RUN \
    apk add --no-cache \
    inkscape \
    ruby \
    ruby-rdoc
COPY . .
RUN \
    gem build inkmake.gemspec && \
    gem install inkmake
ENTRYPOINT ["inkmake"]
