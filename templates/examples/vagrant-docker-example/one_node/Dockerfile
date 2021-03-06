FROM ubuntu:14.04
MAINTAINER OSLL "osll@osll.org"

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && \
    apt-get install -y sudo ssh curl iptables && \
    apt-get clean

RUN mkdir /var/run/sshd

# Create and configure vagrant user
RUN groupadd vagrant
RUN useradd -c "Vagrant" -g vagrant -d /home/vagrant -m -s /bin/bash vagrant
RUN echo 'root:vagrant' | chpasswd

# Enable passwordless sudo for vagrant 
RUN echo 'vagrant ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Configure SSH access
RUN mkdir -p /home/vagrant/.ssh
RUN echo 'ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key' > /home/vagrant/.ssh/authorized_keys
RUN chmod 0600 /home/vagrant/.ssh/authorized_keys
RUN chown -R vagrant:vagrant /home/vagrant/.ssh
RUN chmod 0700 /home/vagrant/.ssh

# Install chef
RUN wget -O - https://www.opscode.com/chef/install.sh | bash && apt-get clean
RUN /opt/chef/embedded/bin/gem install knife-solo -no-ri -no-rdoc

# Clean up APT when done.
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

CMD ["/usr/sbin/sshd", "-D", "-e"]
EXPOSE 22
