# helper image that fills the database with test votes (only runs with --profile seed)
FROM python:3.13-slim-trixie

# add apache bench (ab) tool
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    apache2-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /seed

COPY . .

# create POST data files with ab friendly formats
RUN python make-data.py

# run as a normal user
USER nobody

CMD ["/seed/generate-votes.sh"]
