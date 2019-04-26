#Stage 1 : builder debian image
FROM debian:stretch as builder

# properly setup debian sources
ENV DEBIAN_FRONTEND noninteractive
RUN echo "deb http://http.debian.net/debian stretch main\n\
deb-src http://http.debian.net/debian stretch main\n\
deb http://http.debian.net/debian stretch-updates main\n\
deb-src http://http.debian.net/debian stretch-updates main\n\
deb http://security.debian.org stretch/updates main\n\
deb-src http://security.debian.org stretch/updates main\n\
" > /etc/apt/sources.list

# install package building helpers
# rsyslog for logging (ref https://github.com/stilliard/docker-pure-ftpd/issues/17)
RUN apt-get -y update && \
	apt-get -y --fix-missing install dpkg-dev debhelper &&\
	apt-get -y build-dep pure-ftpd-ldap
	

# build from source to add --without-capabilities flag
RUN mkdir /tmp/pure-ftpd-ldap/ && \
	cd /tmp/pure-ftpd-ldap/ && \
	apt-get source pure-ftpd-ldap && \
	cd pure-ftpd-* && \
	./configure --with-tls --with-ldap | grep -v '^checking' | grep -v ': Entering directory' | grep -v ': Leaving directory' && \
	sed -i '/^optflags=/ s/$/ --without-capabilities/g' ./debian/rules && \
	dpkg-buildpackage -b -uc | grep -v '^checking' | grep -v ': Entering directory' | grep -v ': Leaving directory'


#Stage 2 : actual pure-ftpd image
FROM debian:stretch

# feel free to change this ;)
LABEL maintainer "Meridian Innovation Application Team <meridianinno@gmail.com>"

# install dependencies
# FIXME : libcap2 is not a dependency anymore. .deb could be fixed to avoid asking this dependency
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get -y update && \
	apt-get  --no-install-recommends --yes install \
	openbsd-inetd \
	rsyslog \
	lsb-base \
	libc6 \
	libcap2 \
	libpam0g \
	libssl1.1 \
	libldap-2.4-2 \
	openssl

COPY --from=builder /tmp/pure-ftpd-ldap/*.deb /tmp/pure-ftpd-ldap/

RUN ls /tmp/pure-ftpd-ldap/*.deb

# install the new deb files
RUN dpkg -i /tmp/pure-ftpd-ldap/pure-ftpd-common*.deb &&\
	dpkg -i /tmp/pure-ftpd-ldap/pure-ftpd-ldap*.deb && \
	rm -Rf /tmp/pure-ftpd-ldap

# Prevent pure-ftpd upgrading
RUN apt-mark hold pure-ftpd-ldap pure-ftpd-common

# setup ftpgroup and ftpuser
RUN groupadd ftpgroup &&\
	useradd -g ftpgroup -d /home/ftpusers -s /dev/null ftpuser

# configure rsyslog logging
RUN echo "" >> /etc/rsyslog.conf && \
	echo "#PureFTP Custom Logging" >> /etc/rsyslog.conf && \
	echo "ftp.* /var/log/pure-ftpd/pureftpd.log" >> /etc/rsyslog.conf && \
	echo "Updated /etc/rsyslog.conf with /var/log/pure-ftpd/pureftpd.log"

# setup run/init file
COPY run.sh /run.sh
RUN chmod u+x /run.sh

# setup ldap config (not needed?)
#COPY ldap.conf /ldap.conf
#RUN chmod 600 /ldap.conf

# default publichost, you'll need to set this for passive support
ENV PUBLICHOST localhost

# couple available volumes you may want to use
VOLUME ["/home/ftpusers", "/etc/pure-ftpd/passwd", "/ldap.conf"]

# startup
CMD /run.sh -l puredb:/etc/pure-ftpd/pureftpd.pdb -l ldap:/ldap.conf -E -j -R -P $PUBLICHOST -s -A -j -Z -H -4 -E -R -G -X -x

EXPOSE 21 30000-30009

