FROM alpine:3.6

# Install required packages
RUN apk add --no-cache \
      boost-system \
      boost-thread \
      ca-certificates \
      qt5-qtbase

# Compiling qBitTorrent following instructions on
# https://github.com/qbittorrent/qBittorrent/wiki/Compiling-qBittorrent-on-Debian-and-Ubuntu#Libtorrent

RUN set -x \
    # Install runtime dependencies
 && apk add --no-cache \
        ca-certificates \
        libressl \

    # Install build dependencies
 && apk add --no-cache -t .build-deps \
        boost-dev \
        curl \
        cmake \
        g++ \
        make \
        libressl-dev \

    # Install dumb-init
    # https://github.com/Yelp/dumb-init
 && curl -sSLo /usr/local/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.2.0/dumb-init_1.2.0_amd64 \
 && chmod +x /usr/local/bin/dumb-init \

    # Build lib rasterbar from source code (required by qBittorrent)
    # Until https://github.com/qbittorrent/qBittorrent/issues/6132 is fixed, need to use version 1.0.*
    #  && LIBTORRENT_RASTERBAR_URL=$(curl -sSL https://api.github.com/repos/arvidn/libtorrent/releases/latest | grep browser_download_url  | head -n 1 | cut -d '"' -f 4) \
 && LIBTORRENT_RASTERBAR_URL=https://github.com/arvidn/libtorrent/releases/download/libtorrent-1_0_11/libtorrent-rasterbar-1.0.11.tar.gz \
 && mkdir /tmp/libtorrent-rasterbar \
 && curl -sSL $LIBTORRENT_RASTERBAR_URL | tar xzC /tmp/libtorrent-rasterbar \
 && cd /tmp/libtorrent-rasterbar/* \
 && mkdir build \
 && cd build \
 && cmake .. \
 && make install \

    # Clean-up
 && cd / \
 && apk del --purge .build-deps \
 && rm -rf /tmp/*

COPY main.patch /

RUN set -x \
    # Install build dependencies
 && apk add --no-cache -t .build-deps \
        boost-dev \
        g++ \
        git \
        make \
        qt5-qttools-dev \

    # Build qBittorrent from source code
 && git clone https://github.com/qbittorrent/qBittorrent.git /tmp/qbittorrent \
 && cd /tmp/qbittorrent \
    # Checkout latest release
 && latesttag=$(git describe --tags `git rev-list --tags --max-count=1`) \
 && git checkout $latesttag \
    # Compile
 && PKG_CONFIG_PATH=/usr/local/lib/pkgconfig ./configure --disable-gui \
    # Patch: Disable stack trace because it requires libexecline-dev which isn't available on Alpine 3.6.
 && cd src/app \
 && patch -i /main.patch \
 && rm /main.patch \
 && cd ../.. \
 && make install \

    # Clean-up
 && cd / \
 && apk del --purge .build-deps \
 && rm -rf /tmp/* \

    # Add non-root user
 && adduser -S -D -u 520 -g 520 -s /sbin/nologin qbittorrent \

    # Create symbolic links to simplify mounting
 && mkdir -p /home/qbittorrent/.config/qBittorrent \
 && mkdir -p /home/qbittorrent/.local/share/data/qBittorrent \
 && mkdir /downloads \
 && chmod go+rw -R /home/qbittorrent /downloads \
 && ln -s /home/qbittorrent/.config/qBittorrent /config \
 && ln -s /home/qbittorrent/.local/share/data/qBittorrent /torrents \

    # Check it works
 && su qbittorrent -s /bin/sh -c 'qbittorrent-nox -v'

# Default configuration file.
COPY qBittorrent.conf /default/qBittorrent.conf
COPY entrypoint.sh /

VOLUME ["/config", "/torrents", "/downloads"]

ENV HOME=/home/qbittorrent

USER qbittorrent

EXPOSE 8080 6881

ENTRYPOINT ["dumb-init", "/entrypoint.sh"]
CMD ["qbittorrent-nox"]
