FROM ubuntu:20.04

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get install -y \
    sudo

# Create ubuntu user with sudo privileges
ENV USER=mersdk
RUN useradd -ms /bin/bash ${USER} && \
    usermod -aG sudo ${USER}
# New added for disable sudo password
RUN echo 'mersdk ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

RUN curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func=install_sshpass

# Set as default user
USER ${USER}
RUN mkdir -p /home/${USER}/app
RUN mkdir -p /home/${USER}/.ssh
WORKDIR /home/${USER}/app

CMD ["/bin/bash"]
