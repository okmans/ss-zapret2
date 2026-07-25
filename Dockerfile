ARG ALPINE_VERSION=3.21
ARG ZAPRET_TAG=v1.0.3
ARG CURL_VERSION=8.13.0
ARG BLOCKCHECKW_VERSION=v0.9.0

FROM alpine:${ALPINE_VERSION} AS build
ARG ZAPRET_TAG
ARG CURL_VERSION
ARG BLOCKCHECKW_VERSION
ARG TARGETPLATFORM
ARG ZAPRET_SRC=/opt/zapret2-src
ARG ZAPRET_BUILD=/opt/zapret2-build
ARG ZAPRET_ARCH
ARG ZAPRET_ARCH_FILE=/tmp/zapret_arch
ARG CURL_ARCH
ARG CURL_ARCH_FILE=/tmp/curl_arch
ARG BLOCKCHECKW_ARCH
ARG BLOCKCHECKW_ARCH_FILE=/tmp/blockcheckw_arch

WORKDIR /opt

RUN <<EOT
  set -euo pipefail
  case ${TARGETPLATFORM} in
    "linux/amd64")
      echo "linux-x86_64" \
      | tee ${ZAPRET_ARCH_FILE} ${BLOCKCHECKW_ARCH_FILE} >/dev/null
      echo "x86_64" >${CURL_ARCH_FILE}
    ;;
    "linux/arm64")
      echo "linux-arm64" \
      | tee ${ZAPRET_ARCH_FILE} ${BLOCKCHECKW_ARCH_FILE} >/dev/null
      echo "aarch64" >${CURL_ARCH_FILE}
    ;;
    *)
      echo "Unsupported platform: $TARGETPLATFORM"
      exit 1
    ;;
  esac
EOT

ADD --unpack "https://github.com/bol-van/zapret2/releases/download/${ZAPRET_TAG}/zapret2-${ZAPRET_TAG}.tar.gz" .
RUN mv zapret2-${ZAPRET_TAG} ${ZAPRET_SRC}

WORKDIR ${ZAPRET_BUILD}

RUN <<EOT
  set -euo pipefail
  ZAPRET_ARCH=$(cat ${ZAPRET_ARCH_FILE})
  mkdir -p binaries/${ZAPRET_ARCH}
  install -t binaries/${ZAPRET_ARCH}/ \
    ${ZAPRET_SRC}/binaries/${ZAPRET_ARCH}/ip2net \
    ${ZAPRET_SRC}/binaries/${ZAPRET_ARCH}/mdig \
    ${ZAPRET_SRC}/binaries/${ZAPRET_ARCH}/nfqws2
EOT

RUN <<EOT
  set -euo pipefail
  cp -at . \
    ${ZAPRET_SRC}/init.d \
    ${ZAPRET_SRC}/common \
    ${ZAPRET_SRC}/ipset \
    ${ZAPRET_SRC}/blockcheck2.d \
    ${ZAPRET_SRC}/blockcheck2.sh
  cp -a ${ZAPRET_SRC}/files files
  mv files/fake files/fake.dist
  cp -a ${ZAPRET_SRC}/lua lua.dist
  mv init.d/custom.d.examples.linux init.d/custom.d.examples.linux.dist
  find init.d -mindepth 1 -maxdepth 1 -type d \
    ! -name "sysv" \
    ! -name "files" \
    ! -name "custom.d.examples.*" \
    -exec rm -rf {} \+
EOT

RUN ZAPRET_BASE=${ZAPRET_BUILD} ${ZAPRET_SRC}/install_bin.sh

RUN CURL_ARCH=$(cat ${CURL_ARCH_FILE}) && \
    wget -qO- "https://github.com/stunnel/static-curl/releases/download/${CURL_VERSION}/curl-linux-${CURL_ARCH}-glibc-${CURL_VERSION}.tar.xz" | \
    tar -xJf - -C /opt && \
    chmod +x /opt/curl

RUN BLOCKCHECKW_ARCH=$(cat ${BLOCKCHECKW_ARCH_FILE}) && \
    wget -qO- "https://github.com/rcd27/blockcheckw/releases/download/${BLOCKCHECKW_VERSION}/blockcheckw-${BLOCKCHECKW_ARCH}.tar.gz" | \
    tar -xzf - -C /opt && \
    chmod +x /opt/blockcheckw


FROM alpine:${ALPINE_VERSION}

RUN ["apk", "add", "--no-cache", \
     "ipset", \
     "iptables", \
     "ip6tables", \
     "nftables", \
     "netcat-openbsd"]
RUN ["apk", "add", "--no-cache", \
     "-X", "https://dl-cdn.alpinelinux.org/alpine/edge/testing", \
     "shadowsocks-libev"]

EXPOSE 1080 8388

WORKDIR /opt

COPY --from=build /opt/zapret2-build /opt/zapret2
COPY --from=build /opt/curl /usr/bin/curl
COPY --from=build /opt/blockcheckw /usr/bin/blockcheckw
COPY --chmod=755 entrypoint.sh /opt/entrypoint.sh

ENTRYPOINT ["/opt/entrypoint.sh"]
