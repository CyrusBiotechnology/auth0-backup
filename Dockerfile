FROM ubuntu:18.04
RUN apt-get update && apt-get install -y curl gnupg jq
RUN echo "deb http://packages.cloud.google.com/apt gcsfuse-bionic main" | tee /etc/apt/sources.list.d/gcsfuse.list
RUN curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
RUN apt-get update & apt-get install -y --allow-unauthenticated gcsfuse
COPY backup.sh /usr/local/bin/
CMD [ "backup.sh" ]