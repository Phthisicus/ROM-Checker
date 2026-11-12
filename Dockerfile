FROM node:24-alpine AS frontend
WORKDIR /src
COPY web/client/package*.json ./
RUN npm ci --no-fund --no-audit
COPY web/client/ ./
COPY .github/release-tools/build-info.mjs ./build-info.mjs
COPY release-info.json ./release-info.json
ARG VERSION=0.0.0-local
ARG REVISION=development
ARG BUILD_NUMBER=0
ARG BUILD_ATTEMPT=0
ARG CHANNEL=local
ARG BUILT_UTC
ARG WORKFLOW_URL
RUN node build-info.mjs && npm run build && cp build-info.json dist/build-info.json

FROM mcr.microsoft.com/dotnet/sdk:10.0-noble AS backend
WORKDIR /src
COPY web/server/RomChecker.Web.csproj web/server/
RUN dotnet restore web/server/RomChecker.Web.csproj
COPY web/server/ web/server/
RUN dotnet publish web/server/RomChecker.Web.csproj -c Release -o /out --no-restore /p:UseAppHost=false

FROM scratch AS release-metadata
COPY --from=frontend /src/release-info.json /release-info.json

FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble AS runtime
ARG VERSION=0.0.0-local
ARG REVISION=development
ARG BUILD_NUMBER=0
ARG BUILD_ATTEMPT=0
ARG CHANNEL=local
ARG BUILT_UTC
ARG WORKFLOW_URL
LABEL org.opencontainers.image.title="ROM Checker" \
      org.opencontainers.image.description="Self-hosted ROM verification and organization workspace" \
      org.opencontainers.image.source="https://github.com/Phthisicus/ROM-Checker" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${BUILT_UTC}" \
      io.romchecker.build-number="${BUILD_NUMBER}" \
      io.romchecker.build-attempt="${BUILD_ATTEMPT}" \
      io.romchecker.channel="${CHANNEL}" \
      io.romchecker.workflow-url="${WORKFLOW_URL}" \
      io.romchecker.metadata-format-version="1" \
      io.romchecker.schema-version="1"
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && curl -fsSLo /tmp/packages-microsoft-prod.deb https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb \
    && dpkg -i /tmp/packages-microsoft-prod.deb \
    && rm /tmp/packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends powershell clamav clamav-freshclam 7zip \
    && rm -rf /var/lib/apt/lists \
    && groupadd --gid 10001 romchecker \
    && useradd --uid 10001 --gid 10001 --create-home romchecker \
    && mkdir -p /app /data /library /storage /var/lib/clamav \
    && chown -R 10001:10001 /data /library /storage /var/lib/clamav
WORKDIR /app
COPY --from=backend /out/ ./
COPY --from=frontend /src/dist/ ./web/client/dist/
COPY --from=frontend /src/build-info.json ./build-info.json
COPY --from=frontend /src/release-info.json ./release-info.json
COPY --from=frontend /src/release-notes.md ./release-notes.md
COPY RomSorter.ps1 ./
COPY web/engine/ ./web/engine/
COPY deploy/freshclam.conf /etc/clamav/freshclam.conf
RUN sed -i 's/\r$//' /etc/clamav/freshclam.conf
COPY README.md ./README.md
COPY LICENSE ./LICENSE
ENV ASPNETCORE_URLS=http://+:8080 \
    ROMCHECKER_ENGINE=/app \
    ROMCHECKER_LIBRARY=/library \
    ROMCHECKER_DATA=/data \
    ROMCHECKER_VERSION=${VERSION} \
    ROMCHECKER_COMMIT=${REVISION} \
    DOTNET_EnableDiagnostics=0
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl --fail --silent "http://127.0.0.1:8080${ROMCHECKER_PATH_BASE}/healthz" || exit 1
ENTRYPOINT ["dotnet", "RomChecker.Web.dll"]
