FROM debian:stable-slim

RUN apt-get -y update                            \
&&  apt-get -y install                           \
# Those are likely essential
    git                                          \
# To be removed
    # see  b/164026334
    cpio                                         \
    libc6-dev                                    \
    libgcc-8-dev                                 \
    libssl-dev                                   \
    rsync                                        \
&& apt-get clean                                 \
&& rm -rf /var/lib/apt/lists/*

# Explicitly allow some host binaries for now
RUN mkdir -p /l/bin
RUN ln -s $(which cpio) /l/bin/      # b/164026334
RUN ln -s $(which perl) /l/bin/
RUN ln -s $(which rsync) /l/bin/
RUN ln -s $(which sh) /l/bin/
RUN ln -s $(which tar) /l/bin/       # b/164013907

# Copy the build runner
COPY build /l/build

# Run the build runner if no other command is given
CMD /l/build

