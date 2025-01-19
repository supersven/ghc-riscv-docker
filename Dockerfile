ARG GHC_VERSION

ARG GHC_VERSION_BUILD=${GHC_VERSION}

FROM glcr.b-data.ch/ghc/ghc-musl:9.10.1 AS bootstrap

RUN case "$(uname -m)" in \
    x86_64) linker="gold" ;; \
    aarch64) linker="gold" ;; \
  esac \
  && apk upgrade --no-cache \
  && apk add --no-cache \
    autoconf \
    automake \
    binutils${linker:+-}${linker} \
    build-base \
    clang18 \
    coreutils \
    cpio \
    curl \
    gnupg \
    linux-headers \
    libffi-dev \
    llvm18 \
    ncurses-dev \
    perl \
    python3 \
    xz \
    zlib-dev

# Configure coredumps
RUN apk add --no-cache gdb coreutils && \
    echo "kernel.core_pattern=/coredump/core-%e.%p.%t" >> /etc/sysctl.conf && \
    mkdir -p /coredump && chmod 777 /coredump

FROM bootstrap AS bootstrap-ghc

ARG GHC_VERSION_BUILD

ENV GHC_VERSION=${GHC_VERSION_BUILD}

# Update cabal stuff early to benefit from caching if the later GHC build fails.
RUN cabal update \
    && cabal install alex happy

WORKDIR /tmp

# N.B. I've omitted signature checking to simplify the bulld expression.
RUN wget https://downloads.haskell.org/~ghc/"$GHC_VERSION"/ghc-"$GHC_VERSION"-src.tar.xz \
  && tar -xJf "ghc-$GHC_VERSION-src.tar.xz" \
  && wget https://downloads.haskell.org/~ghc/"$GHC_VERSION"/ghc-"$GHC_VERSION"-testsuite.tar.xz \
  && tar -xJf "ghc-$GHC_VERSION-testsuite.tar.xz"


ENV FLAVOUR="validate+assertions+debug_ghc"

WORKDIR /tmp/ghc-$GHC_VERSION

# Configure and build
RUN ./boot.source \
  && ./configure \
  && export PATH=/root/.local/bin:$PATH \
  && hadrian/build -j --flavour=$FLAVOUR --docs=none


FROM bootstrap-ghc AS test-ghc

WORKDIR /tmp/ghc-$GHC_VERSION

RUN hadrian/build test -j10 --flavour=$FLAVOUR --config="config.timeout=7200" --docs=none -k || true
