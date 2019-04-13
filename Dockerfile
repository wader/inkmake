FROM alpine:3.9
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