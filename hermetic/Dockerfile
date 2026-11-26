FROM debian:stable-slim

RUN apt-get -y update                            \
&&  apt-get -y install                           \
    python3                                      \
    rsync                                        \
&& apt-get clean                                 \
&& rm -rf /var/lib/apt/lists/*

# Explicitly allow some host binaries for now
# TODO(b/228105413): Drop this list once bazel.py no longer uses the provided
#   PATH.
RUN mkdir -p /l/bin
# List in declare_host_tools.bzl
RUN ln -s $(which perl) /l/bin/
RUN ln -s $(which rsync) /l/bin/
RUN ln -s $(which sh) /l/bin/
RUN ln -s $(which bash) /l/bin/
RUN ln -s $(which find) /l/bin/
# b/348003050
RUN ln -s $(which readlink) /l/bin/

# Copy the build runner
COPY build /l/build
RUN chmod a+rx /l/build

# Satisfy some bazel requirements to locate a writable cache directory
RUN chmod 777 /home
ENV USER=build
ENV HOME=/home

# Run the build runner if no other command is given
CMD /l/build

