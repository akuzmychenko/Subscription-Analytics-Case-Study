FROM rocker/shiny:4.4.3
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends libsqlite3-dev zip \
    && rm -rf /var/lib/apt/lists/*
COPY setup.R setup.R
RUN Rscript --vanilla setup.R
COPY . .
ENV APP_HOST=0.0.0.0
EXPOSE 3839
CMD ["Rscript", "--vanilla", "start.R"]
