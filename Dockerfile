# Build backend binary file
FROM golang:1.27.1-alpine3.24 AS be-builder
WORKDIR /go/src/github.com/mayswind/ezbookkeeping
RUN apk --no-cache add git gcc g++ libc-dev
# Source and build metadata changes must not invalidate dependency downloads.
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG RELEASE_BUILD
ARG BUILD_PIPELINE
ARG BUILD_UNIXTIME
ARG BUILD_DATE
ARG CHECK_3RD_API
ARG SKIP_TESTS
ENV RELEASE_BUILD=$RELEASE_BUILD
ENV BUILD_PIPELINE=$BUILD_PIPELINE
ENV BUILD_UNIXTIME=$BUILD_UNIXTIME
ENV BUILD_DATE=$BUILD_DATE
ENV CHECK_3RD_API=$CHECK_3RD_API
ENV SKIP_TESTS=$SKIP_TESTS
RUN docker/backend-build-pre-setup.sh
RUN ./build.sh backend

# Build frontend files
FROM --platform=$BUILDPLATFORM node:26.8.1-alpine3.24 AS fe-builder
WORKDIR /go/src/github.com/mayswind/ezbookkeeping
RUN apk --no-cache add git
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ARG RELEASE_BUILD
ARG BUILD_PIPELINE
ARG BUILD_UNIXTIME
ARG BUILD_DATE
ARG BUILD_NODE_OPTIONS
ENV RELEASE_BUILD=$RELEASE_BUILD
ENV BUILD_PIPELINE=$BUILD_PIPELINE
ENV BUILD_UNIXTIME=$BUILD_UNIXTIME
ENV BUILD_DATE=$BUILD_DATE
ENV NODE_OPTIONS=$BUILD_NODE_OPTIONS
RUN docker/frontend-build-pre-setup.sh
RUN ./build.sh frontend

# Package docker image
FROM alpine:3.24.1
LABEL maintainer="MaysWind <i@mayswind.net>"
RUN addgroup -S -g 1000 ezbookkeeping && adduser -S -G ezbookkeeping -u 1000 ezbookkeeping
RUN apk --no-cache add tzdata
COPY docker/docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
RUN mkdir -p /ezbookkeeping && chown 1000:1000 /ezbookkeeping \
  && mkdir -p /ezbookkeeping/data && chown 1000:1000 /ezbookkeeping/data \
  && mkdir -p /ezbookkeeping/log && chown 1000:1000 /ezbookkeeping/log \
  && mkdir -p /ezbookkeeping/storage && chown 1000:1000 /ezbookkeeping/storage
WORKDIR /ezbookkeeping
COPY --from=be-builder --chown=1000:1000 /go/src/github.com/mayswind/ezbookkeeping/ezbookkeeping /ezbookkeeping/ezbookkeeping
COPY --from=fe-builder --chown=1000:1000 /go/src/github.com/mayswind/ezbookkeeping/dist /ezbookkeeping/public
COPY --chown=1000:1000 conf /ezbookkeeping/conf
COPY --chown=1000:1000 templates /ezbookkeeping/templates
COPY --chown=1000:1000 LICENSE /ezbookkeeping/LICENSE
# Allow writing root-owned persistent volumes when the platform cannot set a securityContext.
USER 0:0
EXPOSE 8080
ENTRYPOINT ["/docker-entrypoint.sh"]
