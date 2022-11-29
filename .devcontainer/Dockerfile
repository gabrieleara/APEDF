FROM mcr.microsoft.com/devcontainers/universal:2-linux

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
	--no-install-recommends \
	git bc bison flex libssl-dev make libc6-dev libncurses5-dev kmod \
	crossbuild-essential-armhf \
	crossbuild-essential-arm64 \
	sshfs \
	&& rm -rf /var/lib/apt/lists/*
