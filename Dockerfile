FROM lanol/filecodebox:beta

RUN apt-get update && apt-get install -y \
    python3-pip \
    git \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir huggingface_hub datasets

RUN useradd -m -u 1000 user

WORKDIR /app

ENV HOME=/home/user \
    PATH=/home/user/.local/bin:$PATH \
    HF_HOME=/app/data/hf_cache \
    PYTHONUNBUFFERED=1

RUN mkdir -p /app/data && \
    chown -R user:user /app/data

COPY sync_data.sh /app/
RUN chmod +x /app/sync_data.sh && \
    chown user:user /app/sync_data.sh

USER user

EXPOSE 12345

ENTRYPOINT ["/app/sync_data.sh"]