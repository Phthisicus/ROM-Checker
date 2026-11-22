FROM scratch
ARG CHANNEL
ARG VERSION
ARG BUILD_VERSION
ARG IMAGE
ARG IMAGE_TAG
ARG IMAGE_DIGEST
ARG COMMIT
ARG BUILD_NUMBER
ARG SCHEMA_VERSION
ARG PUBLISHED_UTC
ARG RELEASE_NOTES_URL
LABEL io.romchecker.manifest-format-version="1" \
      io.romchecker.channel="${CHANNEL}" \
      io.romchecker.version="${VERSION}" \
      io.romchecker.build-version="${BUILD_VERSION}" \
      io.romchecker.image="${IMAGE}" \
      io.romchecker.image-tag="${IMAGE_TAG}" \
      io.romchecker.image-digest="${IMAGE_DIGEST}" \
      io.romchecker.commit="${COMMIT}" \
      io.romchecker.build-number="${BUILD_NUMBER}" \
      io.romchecker.schema-version="${SCHEMA_VERSION}" \
      io.romchecker.published-utc="${PUBLISHED_UTC}" \
      io.romchecker.release-notes-url="${RELEASE_NOTES_URL}"
