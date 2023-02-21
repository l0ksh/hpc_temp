FROM almalinux:8.7

MAINTAINER The xCAT Project

ENV container docker

ARG xcat_version=latest
ARG xcat_reporoot=https://xcat.org/files/xcat/repos/yum
ARG xcat_baseos=rh8

COPY ./contrib/config /opt/openshift/config
COPY ./contrib/lib /opt/openshift/lib

# Add startup scripts
COPY ./contrib/run-*.sh /usr/local/bin/
COPY ./contrib/*.ldif /usr/local/etc/openldap/
COPY ./contrib/*.schema /usr/local/etc/openldap/
COPY ./contrib/DB_CONFIG /usr/local/etc/openldap/

# Add test query
COPY test1/test.ldif /test/test.ldif

RUN (cd /lib/systemd/system/sysinit.target.wants/; \
     for i in *; do [ $i == systemd-tmpfiles-setup.service ] || rm -f $i; done); \
        rm -f /lib/systemd/system/multi-user.target.wants/* && \
        rm -f /etc/systemd/system/*.wants/* && \
        rm -f /lib/systemd/system/local-fs.target.wants/* && \
        rm -f /lib/systemd/system/sockets.target.wants/*udev* && \
        rm -f /lib/systemd/system/sockets.target.wants/*initctl* && \
        rm -f /lib/systemd/system/basic.target.wants:/* && \
        rm -f /lib/systemd/system/anaconda.target.wants/*

RUN mkdir -p /xcatdata/etc/{dhcp,goconserver,xcat} && ln -sf -t /etc /xcatdata/etc/{dhcp,goconserver,xcat} && \
    mkdir -p /xcatdata/{install,tftpboot} && ln -sf -t / /xcatdata/{install,tftpboot}


RUN yum install -y -q wget which &&\
    wget ${xcat_reporoot}/${xcat_version}/$([[ "devel" = "${xcat_version}" ]] && echo 'core-snap' || echo 'xcat-core')/xcat-core.repo -O /etc/yum.repos.d/xcat-core.repo && \
    wget ${xcat_reporoot}/${xcat_version}/xcat-dep/${xcat_baseos}/$(uname -m)/xcat-dep.repo -O /etc/yum.repos.d/xcat-dep.repo && \
    yum install -y \
       xCAT \
       openssh-server \
       rsyslog \
       createrepo \
       iproute \
       chrony \
       dhcp-client \
       man && \
    yum clean all

RUN wget -q https://repo.symas.com/configs/SOFL/rhel8/sofl.repo -O /etc/yum.repos.d/sofl.repo &&\
    yum install -y \
    symas-openldap-clients \
    symas-openldap-servers \
    git findutils make \
    openssl procps-ng &&\
    setcap 'cap_net_bind_service=+ep' /usr/sbin/slapd && \
    mkdir -p /var/lib/ldap && \
    chmod a+rwx -R /var/lib/ldap && \
    mkdir -p /etc/openldap && \
    chmod a+rwx -R /etc/openldap && \
    mkdir -p /var/run/openldap && \
    chmod a+rwx -R /var/run/openldap && \
    chmod -R a+rw /opt/openshift

RUN sed -i -e 's|#PermitRootLogin yes|PermitRootLogin yes|g' \
           -e 's|#Port 22|Port 2200|g' \
           -e 's|#UseDNS yes|UseDNS no|g' /etc/ssh/sshd_config && \
    echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config && \
    echo "root:cluster" | chpasswd && \
    rm -rf /root/.ssh && \
    mv /xcatdata /xcatdata.NEEDINIT

RUN systemctl enable httpd && \
    systemctl enable sshd && \
    systemctl enable dhcpd && \
    systemctl enable rsyslog && \
    systemctl enable xcatd

ADD compute.alma8.pkglist .
ADD compute.alma8.tmpl .
ADD compute.alma8.x86_64.exlist .
ADD compute.alma8.x86_64.pkglist .
ADD compute.alma8.x86_64.postinstall .
ADD geninitrd .
ADD service.alma8.pkglist .
ADD service.alma8.tmpl .
ADD service.alma8.x86_64.otherpkgs.pkglist .
ADD xcat_customize_alma-8.7.sh .
ADD compute_nodes.sh /

RUN chmod +x xcat_customize_alma-8.7.sh

RUN ./xcat_customize_alma-8.7.sh




ADD entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV XCATROOT /opt/xcat
ENV PATH="$XCATROOT/bin:$XCATROOT/sbin:$XCATROOT/share/xcat/tools:$PATH" MANPATH="$XCATROOT/share/man:$MANPATH"
VOLUME [ "/xcatdata", "/var/log/xcat" ]

# Set OpenLDAP data and config directories in a data volume
VOLUME ["/var/lib/ldap", "/etc/openldap"]

# Expose default ports for ldap and ldaps
EXPOSE 389 636

CMD ["/usr/local/bin/run-openldap.sh"]

CMD [ "/entrypoint.sh" ]

