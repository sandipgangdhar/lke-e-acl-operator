FROM alpine:3.20

RUN apk add --no-cache \
    bash \
    curl \
    jq \
    ca-certificates \
    kubectl

WORKDIR /app

USER root

CMD ["/bin/sh"]
