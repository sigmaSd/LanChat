FROM gitpod/workspace-full-vnc

ENV FLUTTER_HOME=/home/gitpod/flutter \
    FLUTTER_VERSION=v1.9.1+hotfix.6-stable
# Install dart
USER root

RUN curl https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - && \
    apt-get update && \
    apt-get -y install libpulse0 build-essential libkrb5-dev gcc make && \
    apt-get clean && \
    apt-get -y autoremove && \
    apt-get -y clean && \
    rm -rf /var/lib/apt/lists/*;

# Install android studio
RUN add-apt-repository ppa:maarten-fonville/android-studio && \
    apt-get update && \
    apt-get install android-sdk \
        lib32stdc++6 \
        android-studio \
        android-sdk-build-tools \
        android-sdk \
        android-sdk-platform-23 --no-install-recommends --yes

USER gitpod

# Install Flutter sdk
RUN cd /home/gitpod && \
  wget -qO flutter_sdk.tar.xz https://storage.googleapis.com/flutter_infra/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}.tar.xz && \
  tar -xvf flutter_sdk.tar.xz && rm flutter_sdk.tar.xz

# linux is available on master channel
RUN $FLUTTER_HOME/bin/flutter channel master && $FLUTTER_HOME/bin/flutter upgrade && $FLUTTER_HOME/bin/flutter config --enable-linux

# Change the PUB_CACHE to /workspace so dependencies are preserved.
ENV PUB_CACHE=/workspace/.pub_cache

# add executables to PATH
RUN echo 'export PATH=${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PUB_CACHE}/bin:${FLUTTER_HOME}/.pub-cache/bin:$PATH' >>~/.bashrc
