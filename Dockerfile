FROM postgres:9.5
MAINTAINER Oded Lazar <oded@senexx.com>

RUN apt-get update && apt-get install -y netcat \
                                         libyaml-dev \
                                         libpq-dev \
                                         python-dev \
                                         curl \
                                         dnsutils \
                                         gcc

RUN mkdir -p /home/postgres

RUN curl -fSL 'https://bootstrap.pypa.io/get-pip.py' | python2 && \
    pip install --no-cache-dir --upgrade

ENV FILENAME="governor-1.0"
ENV PYTHON_EGG_CACHE="/tmp"
ADD dist/$FILENAME.tar.gz /tmp
ADD postgres.yml /
#RUN mv /docker-entrypoint.sh /postgres-entrypoint.sh
ADD scripts/entrypoint.sh /docker-entrypoint.sh
RUN chown -R postgres /postgres.yml

RUN cd /tmp/$FILENAME \
    && python setup.py install \
    && chown -R postgres:postgres /home/postgres
