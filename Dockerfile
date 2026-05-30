FROM rocker/r-ver:4.4.2

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libgit2-dev \
    && rm -rf /var/lib/apt/lists/*

# Pin renv 1.2.3; install jsonlite for diagnostic scripts; use PPM Noble binaries throughout
ENV PPM_URL=https://packagemanager.posit.co/cran/__linux__/noble/latest
RUN R -e "\
  options(repos = c(CRAN = Sys.getenv('PPM_URL', '${PPM_URL}'))); \
  install.packages(c('remotes', 'jsonlite')); \
  remotes::install_version('renv', version = '1.2.3', upgrade = 'never')"

# Allow diagnostic scripts to see system-level jsonlite when renv project is active.
ENV RENV_CONFIG_EXTERNAL_LIBRARIES=/usr/local/lib/R/site-library

# System-wide default repo so every R session sees PPM
RUN echo "options(repos = c(CRAN = \"${PPM_URL}\"))" >> /usr/local/lib/R/etc/Rprofile.site

COPY scripts/   /scripts/
COPY templates/ /templates/
COPY fixtures/  /fixtures/
RUN chmod +x /scripts/run_scenario.sh

RUN mkdir -p /artifacts /project

WORKDIR /project
ENTRYPOINT ["/scripts/run_scenario.sh"]
