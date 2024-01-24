FROM golang:1.20.12-alpine3.18 AS Builder

RUN sed -i 's/https:\/\/dl-cdn.alpinelinux.org/http:\/\/mirrors.tuna.tsinghua.edu.cn/' /etc/apk/repositories && \
    echo "Asia/Shanghai" > /etc/timezone

ENV DRONE_VERSION 2.21.0
ENV CGO_CFLAGS="-g -O2 -Wno-return-local-addr"

# Build with online code
RUN apk --no-cache add curl build-base

WORKDIR /src
RUN curl -L -s https://github.com/harness/gitness/archive/refs/tags/v${DRONE_VERSION}.tar.gz -o v${DRONE_VERSION}.tar.gz && \
    tar zxvf v${DRONE_VERSION}.tar.gz && rm v${DRONE_VERSION}.tar.gz
# OR with offline tarball
# ADD drone-1.10.1.tar.gz /src/

WORKDIR /src/gitness-${DRONE_VERSION}
RUN \
    go env -w GO111MODULE=on && \
    go env -w GOPROXY=https://goproxy.cn,direct && \
    go mod download && \
    go build -ldflags "-extldflags \"-static\"" -tags="nolimit" github.com/drone/drone/cmd/drone-server


WORKDIR /src
RUN curl -L -s https://github.com/harness/drone-cli/archive/refs/tags/v1.7.0.tar.gz -o drone-cli.tar.gz && \
  tar zxvf drone-cli.tar.gz && rm drone-cli.tar.gz
WORKDIR /src/drone-cli-1.7.0
RUN go mod download && go build -o drone-cli github.com/drone/drone-cli/drone

FROM alpine:3.15 AS Certs
RUN sed -i 's/https:\/\/dl-cdn.alpinelinux.org/http:\/\/mirrors.tuna.tsinghua.edu.cn/' /etc/apk/repositories && \
    echo "Asia/Shanghai" > /etc/timezone
RUN apk add -U --no-cache ca-certificates

FROM alpine:3.15
EXPOSE 80 443
VOLUME /data

RUN [ ! -e /etc/nsswitch.conf ] && echo 'hosts: files dns' > /etc/nsswitch.conf

ENV GODEBUG netdns=go
ENV XDG_CACHE_HOME /data
ENV DRONE_DATABASE_DRIVER sqlite3
ENV DRONE_DATABASE_DATASOURCE /data/database.sqlite
ENV DRONE_RUNNER_OS=linux
ENV DRONE_RUNNER_ARCH=amd64
ENV DRONE_SERVER_PORT=:80
ENV DRONE_SERVER_HOST=localhost
ENV DRONE_DATADOG_ENABLED=true
ENV DRONE_DATADOG_ENDPOINT=https://stats.drone.ci/api/v1/series
ENV DRONE_VERSION 2.21.0

COPY --from=Certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=Builder /src/gitness-${DRONE_VERSION}/drone-server /bin/drone-server
COPY --from=Builder /src/drone-cli-1.7.0/drone-cli /bin/drone-cli
ENTRYPOINT ["/bin/drone-server"]
