ARG LIBRE_OFFICE_VER=25.8.4.2
ARG DEMO=false
ARG DB_HOST=db
ARG PGHS_HOST=pghs:8888
ARG XRAD_HOST=xrad:8889
ARG XREPORTS_HOST=xreports:8886

FROM debian:13 AS base

ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt update && apt upgrade -y && apt -y install unzip vim wget curl zip locales

RUN ln -fs /usr/share/zoneinfo/Europe/Moscow /etc/localtime && \
      echo "Europe/Moscow" > /etc/timezone && \
      sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
      sed -i -e 's/# ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen && \
      locale-gen && \
      rm -rf /var/lib/apt/lists/*

ENV LC_ALL=ru_RU.UTF-8
ENV LANG=ru_RU.UTF-8
ENV LANGUAGE=ru_RU:ru

#####################
FROM base AS packages

ARG LIBRE_OFFICE_VER
ARG TARGETARCH
ARG DEMO

WORKDIR /xsquare
## Download XSQUARE
RUN wget https://ftp.xsquare.ru/edu/files/pghs_xrad/6.6.7.7.7.7/xsquare.lcdp.6.6.7.7.7.7_release.zip
RUN unzip xsquare.lcdp.6.6.7.7.7.7_release.zip
RUN if [ "$DEMO" = "true" ]; then \
      mv ./xsquare.lcdp.6.6.7.7.7.7_release/usr/local/xsquare.pghs/demo-config.json \
        ./xsquare.lcdp.6.6.7.7.7.7_release/usr/local/xsquare.pghs/config.json; \
      mv ./xsquare.lcdp.6.6.7.7.7.7_release/usr/local/xsquare.xrad/demo-config.json \
        ./xsquare.lcdp.6.6.7.7.7.7_release/usr/local/xsquare.xrad/config.json; \
      mv ./xsquare.lcdp.6.6.7.7.7.7_release/db/demo-xraddb.xsquare.pgsql \
        ./xsquare.lcdp.6.6.7.7.7.7_release/db/xraddb.xsquare.pgsql; \
      mv ./xsquare.lcdp.6.6.7.7.7.7_release/db/demo-appdb.xsquare.pgsql \
        ./xsquare.lcdp.6.6.7.7.7.7_release/db/appdb.xsquare.pgsql; \
    else \
      mv ./xsquare.lcdp.6.6.7.7.7.7_release/db/simple-core-xraddb.xsquare.pgsql \
        ./xsquare.lcdp.6.6.7.7.7.7_release/db/xraddb.xsquare.pgsql; \
      mv ./xsquare.lcdp.6.6.7.7.7.7_release/db/simple-core-appdb.xsquare.pgsql \
        ./xsquare.lcdp.6.6.7.7.7.7_release/db/appdb.xsquare.pgsql; \
    fi
RUN wget https://ftp.xsquare.ru/edu/files/xdac/6.6.0.4/xsquare.xdac.6.6.0.4.deb
RUN wget https://ftp.xsquare.ru/edu/files/xreports/6.6.1.2/xsquare.xreports.6.6.1.2.deb
## Download pgsql-http client
RUN wget https://ftp.xsquare.ru/files/pgsql-http/v1.7.0.tar.gz
## LibreOffice
RUN case "${TARGETARCH}" in "arm64") \ 
      wget https://downloadarchive.documentfoundation.org/libreoffice/old/${LIBRE_OFFICE_VER}/deb/aarch64/LibreOffice_${LIBRE_OFFICE_VER}_Linux_aarch64_deb.tar.gz -O LibreOffice_${LIBRE_OFFICE_VER}_deb.tar.gz;; \
      "amd64") \
      wget https://downloadarchive.documentfoundation.org/libreoffice/old/${LIBRE_OFFICE_VER}/deb/x86_64/LibreOffice_${LIBRE_OFFICE_VER}_Linux_x86-64_deb.tar.gz -O LibreOffice_${LIBRE_OFFICE_VER}_deb.tar.gz;; \
    esac

####################
FROM postgres:17 AS db

ARG DEMO

WORKDIR /tmp/xsquare

USER root
RUN apt update && apt upgrade -y && \
      apt -y install gcc dpkg-dev postgresql-server-dev-17 libcurl4-openssl-dev locales && \
      rm -rf /var/lib/apt/lists/*

RUN ln -fs /usr/share/zoneinfo/Europe/Moscow /etc/localtime && \
      echo "Europe/Moscow" > /etc/timezone && \
      sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
      sed -i -e 's/# ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen && \
      locale-gen && \
      rm -rf /var/lib/apt/lists/*

COPY --from=packages /xsquare/v1.7.0.tar.gz ./v1.7.0.tar.gz
RUN tar -xzf v1.7.0.tar.gz
ENV PATH=$PATH:/usr/lib/postgresql/17/bin/
RUN echo $PATH
RUN cd pgsql-http-1.7.0 && make && make install

COPY ./db/init/01-init.sh /docker-entrypoint-initdb.d/01-init.sh
COPY --from=packages /xsquare/xsquare.lcdp.6.6.7.7.7.7_release/db/xraddb.xsquare.pgsql /docker-entrypoint-initdb.d/02-xraddb.sql
RUN printf '%s\n%s' '\c xraddb' "$(cat /docker-entrypoint-initdb.d/02-xraddb.sql)" > /docker-entrypoint-initdb.d/02-xraddb.sql
COPY --from=packages /xsquare/xsquare.lcdp.6.6.7.7.7.7_release/db/appdb.xsquare.pgsql /docker-entrypoint-initdb.d/03-appdb.sql
RUN printf '%s\n%s' '\c appdb' "$(cat /docker-entrypoint-initdb.d/03-appdb.sql)" > /docker-entrypoint-initdb.d/03-appdb.sql

USER postgres

#################
FROM base AS pghs

ARG TARGETARCH
ARG DB_HOST

COPY --from=packages /xsquare/xsquare.lcdp.6.6.7.7.7.7_release/usr/local/xsquare.pghs /usr/local/xsquare.pghs

WORKDIR /usr/local/xsquare.pghs

RUN if [ "$TARGETARCH" = "arm64" ]; then \ 
      wget https://ftp.xsquare.ru/edu/files/pghs_xrad/6.6.7.7.7.7/arm64/pghs.arm && \
      chmod +x pghs.arm && \
      mv pghs.arm pghs; \
    fi

RUN sed -i -e "s/\"host\": \"127.0.0.1\"/\"host\": \"${DB_HOST}\"/" config.json

EXPOSE 8888

CMD ["/usr/local/xsquare.pghs/pghs"]


#################
FROM base AS xrad

ARG TARGETARCH
ARG DB_HOST

COPY --from=packages /xsquare/xsquare.lcdp.6.6.7.7.7.7_release/usr/local/xsquare.xrad /usr/local/xsquare.xrad

WORKDIR /usr/local/xsquare.xrad

RUN if [ "$TARGETARCH" = "arm64" ]; then \ 
      wget https://ftp.xsquare.ru/edu/files/pghs_xrad/6.6.7.7.7.7/arm64/xrad.arm && \
      chmod +x xrad.arm && \
      mv xrad.arm xrad; \
    fi

RUN sed -i -e "s/\"host\": \"127.0.0.1\"/\"host\": \"${DB_HOST}\"/" config.json

EXPOSE 8889

CMD ["/usr/local/xsquare.xrad/xrad"]

#################
FROM base AS xdac

ARG TARGETARCH
ARG DB_HOST

COPY --from=packages /xsquare/xsquare.xdac.6.6.0.4.deb .

RUN dpkg -i xsquare.xdac.6.6.0.4.deb

EXPOSE 8887

WORKDIR /usr/local/xsquare.xdac

RUN if [ "$TARGETARCH" = "arm64" ]; then \ 
      wget https://ftp.xsquare.ru/edu/files/xdac/6.6.0.4/arm64/xdac.arm && \
      chmod +x xdac.arm && \
      mv xdac.arm xdac; \
    fi

RUN sed -i -e "s/\"host\": \"127.0.0.1\"/\"host\": \"${DB_HOST}\"/" config.json

CMD ["/usr/local/xsquare.xdac/xdac"]


#####################
FROM base AS xreports

ARG LIBRE_OFFICE_VER
ARG TARGETARCH

WORKDIR /app

COPY --from=packages /xsquare/xsquare.xreports.6.6.1.2.deb .
RUN dpkg -i xsquare.xreports.6.6.1.2.deb
RUN apt update && apt upgrade -y && \
      apt -y install libxinerama1 libcairo2 libcups2 default-jre && \
      rm -rf /var/lib/apt/lists/*

COPY --from=packages /xsquare/LibreOffice_${LIBRE_OFFICE_VER}_deb.tar.gz ./LibreOffice_${LIBRE_OFFICE_VER}_deb.tar.gz
RUN tar -xvzf LibreOffice_${LIBRE_OFFICE_VER}_deb.tar.gz
RUN ls -al
RUN dpkg -i ./LibreOffice_${LIBRE_OFFICE_VER}*_deb/DEBS/*.deb
RUN soffice_path=`find / -name "soffice"` && \
   old_soffice_path='"soffice-path": ""' && \
   new_soffice_path='"soffice-path": "'$soffice_path'"' && \
   sed -i -e "s#$old_soffice_path#$new_soffice_path#g" /usr/local/xsquare.xreports/config.json

EXPOSE 8886

WORKDIR /usr/local/xsquare.xreports

RUN if [ "$TARGETARCH" = "arm64" ]; then \ 
      wget https://ftp.xsquare.ru/edu/files/xreports/6.6.1.2/arm64/xreports.arm && \
      chmod +x xreports.arm && \
      mv xreports.arm xdac; \
    fi

CMD ["/usr/local/xsquare.xreports/xreports"]

####################
FROM nginx AS nginx
ARG PGHS_HOST
ARG XRAD_HOST
ARG XREPORTS_HOST
RUN rm -f /etc/nginx/conf.d/default.conf
COPY --from=packages /xsquare/xsquare.lcdp.6.6.7.7.7.7_release/var /var
COPY --from=packages /xsquare/xsquare.lcdp.6.6.7.7.7.7_release/etc/nginx /etc/nginx
RUN sed -i -e "s#http://127.0.0.1:8888#http://${PGHS_HOST}#g" /etc/nginx/conf.d/pghs.xsquare.conf
RUN sed -i -e "s#http://127.0.0.1:8886#http://${XREPORTS_HOST}#g" /etc/nginx/conf.d/pghs.xsquare.conf
RUN sed -i -e "s#http://127.0.0.1:8889#http://${XRAD_HOST}#g" /etc/nginx/conf.d/xrad.xsquare.conf
