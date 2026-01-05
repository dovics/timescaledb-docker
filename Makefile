NAME=timescaledb
# Default is to timescaledev to avoid unexpected push to the main repo
# Set ORG to timescale in the caller
ORG=timescaledev
PG_VER=pg17
PG_VER_NUMBER=$(shell echo $(PG_VER) | cut -c3-)
PG_MAJOR_VERSION=$(shell echo $(PG_VER_NUMBER) | cut -d. -f1)
ifeq ($(shell test $(PG_MAJOR_VERSION) -ge 16; echo $$?),0)
  ALPINE_VERSION=3.21
  CLANG_VERSION=19
else
  ALPINE_VERSION=3.20
  CLANG_VERSION=15
endif
TS_VERSION=main
PREV_TS_VERSION=$(shell wget --quiet -O - https://raw.githubusercontent.com/timescale/timescaledb/${TS_VERSION}/version.config | grep -P "(previous_version|update_from_version)" | sed -e 's!^[a-z_]\+_version = !!')
PREV_TS_IMAGE="timescale/timescaledb:$(PREV_TS_VERSION)-pg$(PG_VER_NUMBER)$(PREV_EXTRA)"
PREV_IMAGE=$(shell if docker pull $(PREV_TS_IMAGE) >/dev/null; then echo "$(PREV_TS_IMAGE)"; else echo "postgres:$(PG_VER_NUMBER)-alpine"; fi )
# Beta releases should not be tagged as latest, so BETA is used to track.
BETA=1
PLATFORM=linux/386,linux/amd64,linux/arm/v6,linux/arm/v7,linux/arm64

# PUSH_MULTI can be set to nothing for dry-run without pushing during multi-arch build
PUSH_MULTI=--push
TAG_VERSION=$(ORG)/$(NAME):$(TS_VERSION)-$(PG_VER)
TAG_LATEST=$(ORG)/$(NAME):latest-$(PG_VER)
TAG=-t $(TAG_VERSION) $(if $(BETA),,-t $(TAG_LATEST))
TAG_OSS=-t $(TAG_VERSION)-oss $(if $(BETA),,-t $(TAG_LATEST)-oss)

PGVECTOR_VERSION=v0.7.2

COMMON_BUILD_ARGS= --build-arg TS_VERSION=$(TS_VERSION) \
		--build-arg PREV_IMAGE=$(PREV_IMAGE) \
		--build-arg PG_VERSION=$(PG_VER_NUMBER) \
		--build-arg PG_MAJOR_VERSION=$(PG_MAJOR_VERSION) \
		--build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
		--build-arg CLANG_VERSION=$(CLANG_VERSION) \
		--build-arg PGVECTOR_VERSION=$(PGVECTOR_VERSION)

default: image

.multi_$(TS_VERSION)_$(PG_VER)_oss: Dockerfile
	test -n "$(TS_VERSION)"  # TS_VERSION
	test -n "$(PREV_TS_VERSION)"  # PREV_TS_VERSION
	test -n "$(PREV_IMAGE)"  # PREV_IMAGE
	test -n "$(ALPINE_VERSION)"  # ALPINE_VERSION
	docker buildx create --platform $(PLATFORM) --name multibuild --use
	docker buildx inspect multibuild --bootstrap
	docker buildx build --platform $(PLATFORM) \
		$(COMMON_BUILD_ARGS) \
		--build-arg OSS_ONLY=" -DAPACHE_ONLY=1" \
		$(TAG_OSS) $(PUSH_MULTI) .
	touch .multi_$(TS_VERSION)_$(PG_VER)_oss
	docker buildx rm multibuild

.multi_$(TS_VERSION)_$(PG_VER): Dockerfile
	test -n "$(TS_VERSION)"  # TS_VERSION
	test -n "$(PREV_TS_VERSION)"  # PREV_TS_VERSION
	test -n "$(PREV_IMAGE)"  # PREV_IMAGE
	test -n "$(ALPINE_VERSION)"  # ALPINE_VERSION
	docker buildx create --platform $(PLATFORM) --name multibuild --use
	docker buildx inspect multibuild --bootstrap
	docker buildx build --platform $(PLATFORM) \
		$(COMMON_BUILD_ARGS) \
		$(TAG) $(PUSH_MULTI) .
	touch .multi_$(TS_VERSION)_$(PG_VER)
	docker buildx rm multibuild

.build_$(TS_VERSION)_$(PG_VER)_oss: Dockerfile
	docker build $(COMMON_BUILD_ARGS) --build-arg OSS_ONLY=" -DAPACHE_ONLY=1" $(TAG_OSS) .
	touch .build_$(TS_VERSION)_$(PG_VER)_oss

.build_$(TS_VERSION)_$(PG_VER): Dockerfile
	docker build $(COMMON_BUILD_ARGS) $(TAG) .
	touch .build_$(TS_VERSION)_$(PG_VER)

image: .build_$(TS_VERSION)_$(PG_VER)

oss: .build_$(TS_VERSION)_$(PG_VER)_oss

push: image
	docker push $(TAG_VERSION)
	if [ -z "$(BETA)" ]; then \
		docker push $(TAG_LATEST); \
	fi

push-oss: oss
	docker push $(TAG_VERSION)-oss
	if [ -z "$(BETA)" ]; then \
		docker push $(TAG_LATEST)-oss; \
	fi

multi: .multi_$(TS_VERSION)_$(PG_VER)

multi-oss: .multi_$(TS_VERSION)_$(PG_VER)_oss

all: multi multi-oss

clean:
	rm -f *~ .build_* .multi_*
	-docker buildx rm multibuild

# CloudNativePG build settings
CLOUDNATIVEPG_VERSION=$(shell echo $(PG_VER_NUMBER) | awk '{print $$1 == "16" ? "16.11" : $$1 == "17" ? "17.7" : $$1 == "18" ? "18.1" : "17.7"}')
CNPG_TAG_VERSION=$(ORG)/$(NAME):$(CLOUDNATIVEPG_VERSION)-$(TS_VERSION)-standard-trixie
CNPG_TAG_LATEST=$(ORG)/$(NAME):$(PG_VER)-latest-standard-bookworm

CNPG_BUILD_ARGS= --build-arg CLOUDNATIVEPG_VERSION=$(CLOUDNATIVEPG_VERSION) \
		--build-arg POSTGRES_VERSION=$(PG_VER_NUMBER) \
		--build-arg TIMESCALE_VERSION=$(TS_VERSION)

.build_cnpg_$(PG_VER): Dockerfile.cloudnativepg
	test -n "$(CLOUDNATIVEPG_VERSION)"  # CLOUDNATIVEPG_VERSION
	docker build $(CNPG_BUILD_ARGS) -t $(CNPG_TAG_VERSION) -f Dockerfile.cloudnativepg .
	touch .build_cnpg_$(PG_VER)

multi_cnpg: Dockerfile.cloudnativepg
	test -n "$(CLOUDNATIVEPG_VERSION)"  # CLOUDNATIVEPG_VERSION
	docker buildx create --platform linux/amd64,linux/arm64 --name cnpg_multibuild --use
	docker buildx inspect cnpg_multibuild --bootstrap
	docker buildx build --platform linux/amd64,linux/arm64 \
		$(CNPG_BUILD_ARGS) \
		-t $(CNPG_TAG_VERSION) $(PUSH_MULTI) -f Dockerfile.cloudnativepg .
	touch .multi_cnpg_$(PG_VER)
	docker buildx rm cnpg_multibuild

push_cnpg: .build_cnpg_$(PG_VER)
	docker push $(CNPG_TAG_VERSION)

image_cnpg: .build_cnpg_$(PG_VER)

.PHONY: default image push push-oss oss multi multi-oss clean all image_cnpg push_cnpg multi_cnpg
