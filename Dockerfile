# syntax=docker/dockerfile:1.4
# Copyright 2021 Synology Inc.

############## Build stage ##############
FROM golang:1.13.6-alpine as builder
LABEL stage=synobuilder

RUN apk add --no-cache alpine-sdk
WORKDIR /go/src/synok8scsiplugin
COPY go.mod .
RUN go mod download

COPY Makefile .

ARG TARGETPLATFORM

COPY main.go .
COPY pkg ./pkg
RUN env GOARCH=$(echo "$TARGETPLATFORM" | cut -f2 -d/) \
        GOARM=$(echo "$TARGETPLATFORM" | cut -f3 -d/ | cut -c2-) \
        make

############## Final stage ##############
FROM alpine:latest as driver
LABEL maintainers="Synology Authors" \
      description="Synology CSI Plugin"

RUN <<-EOF 
	apk add --no-cache \
		bash \
		blkid \
		btrfs-progs \
		ca-certificates \
		cifs-utils \
		e2fsprogs \
		e2fsprogs-extra \
		iproute2 \
		util-linux \
		xfsprogs \
    open-iscsi \
		xfsprogs-extra
EOF

# Create symbolic link for nsenter.sh
WORKDIR /
COPY --chmod=777 <<-"EOF" /csibin/nsenter.sh
	#!/usr/bin/env bash
	iscsid_pid=$(pgrep iscsid)
	nsenter --mount="/proc/${iscsid_pid}/ns/mnt" --net="/proc/${iscsid_pid}/ns/net" -- /usr/local/sbin/iscsiadm "$@"
EOF
RUN ln -s /csibin/nsenter.sh /csibin/iscsiadm

ENV PATH="/csibin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Copy and run CSI driver
COPY --from=builder /go/src/synok8scsiplugin/bin/synology-csi-driver synology-csi-driver

ENTRYPOINT ["/synology-csi-driver"]
