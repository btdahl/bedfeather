FROM debian:stable-slim
RUN useradd -m -u 1000 bedfeather
RUN apt-get update && apt-get -y install libcurl4 && rm -Rf /var/lib/apt/lists/*
USER bedfeather
WORKDIR /bedrock
COPY . /bedrock
VOLUME /bedrock/worlds
CMD ["./run_fifopipeprocess.sh"]

