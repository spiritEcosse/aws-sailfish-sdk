FROM ubuntu:20.04

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get install -y \
    sudo

# Create ubuntu user with sudo privileges
ENV USER=ubuntu
RUN useradd -ms /bin/bash ${USER} && \
    usermod -aG sudo ${USER}
# New added for disable sudo password
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Set as default user
USER ${USER}
WORKDIR /home/${USER}

# ENV DEBIAN_FRONTEND teletype

CMD ["/bin/bash"]
