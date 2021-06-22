FROM gitpod/workspace-full-vnc

ENV FLUTTER_HOME=/home/gitpod/flutter

# Install dart
USER root

RUN apt-get update && \
    apt-get -y install libgtk-3-dev

USER gitpod

# Install Flutter sdk
RUN cd /home/gitpod && \
  wget -qO flutter_sdk.tar.xz https://storage.googleapis.com/flutter_infra/releases/stable/linux/flutter_linux_2.0.3-stable.tar.xz && \
  tar -xvf flutter_sdk.tar.xz && rm flutter_sdk.tar.xz

RUN $FLUTTER_HOME/bin/flutter upgrade && $FLUTTER_HOME/bin/flutter config --enable-linux-desktop

# Change the PUB_CACHE to /workspace so dependencies are preserved.
ENV PUB_CACHE=/workspace/.pub_cache

# add executables to PATH
RUN echo 'export PATH=${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PUB_CACHE}/bin:${FLUTTER_HOME}/.pub-cache/bin:$PATH' >>~/.bashrc
