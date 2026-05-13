FROM ubuntu:24.04

ARG TARGETARCH
ARG SUMMON_REPO_REF=main
ENV DEBIAN_FRONTEND=noninteractive
ENV SUMMON_HOME=/home/summon
ENV HOME=/home/summon
ENV SUMMON_REPO_REF=${SUMMON_REPO_REF}

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl git bash sudo file \
  && rm -rf /var/lib/apt/lists/* \
  && useradd -m -s /bin/bash summon \
  && echo 'summon ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/summon

WORKDIR /workspace
COPY . /workspace
RUN chown -R summon:summon /workspace /home/summon
USER summon
RUN ./test.sh

CMD ["/bin/bash"]
