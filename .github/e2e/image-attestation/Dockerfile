# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
FROM --platform=$BUILDPLATFORM golang:1.26.2-bookworm@sha256:47ce5636e9936b2c5cbf708925578ef386b4f8872aec74a67bd13a627d242b19 AS build
ARG TARGETOS
ARG TARGETARCH
COPY main.go /src/main.go
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -o /hello /src/main.go
FROM scratch
COPY --from=build /hello /hello
ENTRYPOINT ["/hello"]
