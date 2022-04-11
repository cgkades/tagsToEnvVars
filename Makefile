MAKEFLAGS += --silent

PROJECTNAME=jag

.DEFAULT_GOAL := cmds

SRC_DIR := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
BUILD_DIR := $(SRC_DIR)build
OUTPUT_DIR := $(SRC_DIR)build/output
CACHE_DIR := $(SRC_DIR)build/output/.cache
ARTIFACTS_FILE := $(SRC_DIR)build/output/artifacts.json
BUILD_IMAGE := jag-build-$(shell md5sum $(SRC_DIR)Makefile | cut -d' ' -f 1)
PACKER_IMAGE := jag-packer-$(shell md5sum $(SRC_DIR)Makefile | cut -d' ' -f 1)
HELM_IMAGE := jag-helm-$(shell md5sum $(SRC_DIR)Makefile | cut -d' ' -f 1)
DOCKER_IMAGE_REPO_BASE := docker-analytics-edge-release.dr-uw2.adobeitc.com/jag
UID := $(shell id -u)
GID := $(shell id -g)
GOOS := linux
GOARCH := amd64
VERSION := 2.0.0
RELEASE_BRANCH := main

ARTIFACT_BLANK := {\"%s\":{}}
ARTIFACT_CMD := {\"%s\":{\"platform\":\"$(GOOS)-$(GOARCH)\"}}
ARTIFACT_DOCKER := {\"docker-%s\":{\"type\":\"docker-image\",\"docker:image\":\"%s\",\"docker:repository\":\"%s\",\"docker:tags\":[\"%s\"]}}

# These are similar to what the xeng vcsinfo tool finds
GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
GIT_REV_COUNT := $(shell git rev-list --count HEAD)
GIT_REV := $(shell git rev-parse --short HEAD)
GIT_LAST_MODIFIED_TIME := $(shell git status --porcelain | grep -v 'D  ' | grep -v ' D ' | sed -e "s/^.. //g" -e "s/.* -> //g" | xargs -I x date -r x '+%s' | grep -e '[0123456789]*' | sort -r | head -1)
BUILD_TIMESTAMP := $(shell date '+%s')

# This first looks for the BUILD_NUMBER env var, then falls back to the unix timestamp
BUILD_NUMBER ?= $(shell date '+%s')
BUILD_TYPE := $(shell echo "$(GIT_BRANCH)" | grep -q "^$(RELEASE_BRANCH)$$" && echo "release" || echo "pr")

SEM_VER := $(VERSION)-$(BUILD_TYPE).$(shell echo "$(GIT_BRANCH)" | tr '[:upper:]' '[:lower:]' | sed -e "s/[^0-9a-zA-Z-]/-/g").$(GIT_REV_COUNT).$(GIT_REV).m$(GIT_LAST_MODIFIED_TIME).$(BUILD_NUMBER)

DOCKER_RUN_ARGS := --rm -w /source --mount type=bind,source=$(SRC_DIR),target=/source --mount type=bind,source=$(CACHE_DIR),target=/root/.cache -e CGO_ENABLED=0 -e GOOS=$(GOOS) -e GOARCH=$(GOARCH) -e SEM_VER="$(SEM_VER)" -e BUILD_TIMESTAMP="$(BUILD_TIMESTAMP)" -e BUILD_NUMBER="$(BUILD_NUMBER)" $(BUILD_IMAGE)

# used to run a command in the build container
define run
	docker run $(DOCKER_RUN_ARGS) /bin/sh -c '$1 $2 $3 $4 $5 $6 $7 $8 && chown -R $(UID):$(GID) /source'
endef

define build-docker
	$(call run,./build/update_artifacts_json.sh,$(ARTIFACT_BLANK),docker-$1)
	docker build --no-cache -t "$2" -f "$(BUILD_DIR)/package/docker/Dockerfile.$1" "$(BUILD_DIR)"
	docker run --rm -w /source \
		--mount type=bind,source=$(SRC_DIR),target=/source \
		-e IMG="$$(docker images -q '$2')" \
		$(BUILD_IMAGE) \
		/bin/sh -c './build/update_artifacts_json.sh "$(ARTIFACT_DOCKER)" "$1" "$$IMG" "$2" "$3" && chown -R $(UID):$(GID) /source'
endef

CMDS := $(shell cd cmd && ls)
DOCKER_IMAGES := $(shell cd build/package/docker && ls Dockerfile.* | sed -e 's/^Dockerfile\./docker-image-/g')
PUBLISH_DOCKER_IMAGES := $(shell cd build/package/docker && ls Dockerfile.* | sed -e 's/^Dockerfile\./publish-docker-image-/g')

version:
	echo "$(SEM_VER)"

clean:
	echo "Cleaning..."
	rm -Rf $(OUTPUT_DIR)

update-build-image:
	echo "Updating build image"
	docker build -q -f ./build/Dockerfile.build -t $(BUILD_IMAGE) . > /dev/null
	mkdir -p $(CACHE_DIR)

build-shell: update-build-image
	echo "Starting a build env shell..."
	docker run -it $(DOCKER_RUN_ARGS) /bin/bash

update-packer-image:
	echo "Updating packer image"
	docker build -q -f ./build/package/packer/Dockerfile.packer -t $(PACKER_IMAGE) . > /dev/null

update-helm-image:
	echo "Updating helm image"
	docker build -q -f ./build/package/helm/Dockerfile.helm -t $(HELM_IMAGE) . > /dev/null

protoc: update-build-image
	echo "Building proto/grpc files and documentation..."
	$(call run,./build/build_proto.sh)

unit-tests: update-build-image
	echo "Running tests"
	$(call run,./build/run_tests.sh)

cmds: $(CMDS)

%: cmd/%/main.go unit-tests
	echo "Building $*"
	$(call run,./build/run_cmd_build.sh,$*)

# add these targets here since we don't build exes for these images and the docker-image-% pattern requires a jag-%
jag-envoy jag-envoy-bootstrapper: update-build-image

docker-images: $(DOCKER_IMAGES)

docker-image-%: build/package/docker/Dockerfile.% jag-%
	echo "Building $* Docker image"
	$(call build-docker,$*,$(DOCKER_IMAGE_REPO_BASE)/$*:$(SEM_VER),$(SEM_VER))

publish-docker-images: $(PUBLISH_DOCKER_IMAGES)

publish-docker-image-%: docker-image-%
	echo "Publishing $* Docker image"
	docker push "$(DOCKER_IMAGE_REPO_BASE)/$*:$(SEM_VER)"

helm-chart: update-build-image update-helm-image
	echo "Packaging helm chart"
	rm -f "$(OUTPUT_DIR)/jag-*.tgz"
	docker run --rm -w /source/build/output --mount type=bind,source=$(SRC_DIR),target=/source \
		--entrypoint '' \
		-e VERSION=$(SEM_VER) \
		-e DOCKER_IMAGE_TAG=$(SEM_VER) \
		$(HELM_IMAGE) \
		/source/build/package/helm/package.sh /source/build/package/helm/jag
	$(call run,./build/update_artifacts_json.sh,$(ARTIFACT_BLANK),jag-$(SEM_VER).tgz)

publish-helm-chart: helm-chart
	echo "Publishing helm chart"
	docker run --rm -w /source/build/output --mount type=bind,source=$(SRC_DIR),target=/source \
		--entrypoint '' \
		-e ARTIFACTORY_API_TOKEN=$(ARTIFACTORY_API_TOKEN) \
		$(HELM_IMAGE) \
		/source/build/package/helm/publish.sh jag-$(SEM_VER).tgz

packer: cmds update-packer-image
	echo "Running packer build"
	docker run --rm -w /source \
		--mount type=bind,source=$(SRC_DIR),target=/source \
		-e AWS_ACCESS_KEY_ID=$(AWS_ACCESS_KEY_ID) \
		-e AWS_SECRET_ACCESS_KEY=$(AWS_SECRET_ACCESS_KEY) \
		-e AWS_SESSION_TOKEN=$(AWS_SESSION_TOKEN) \
		$(PACKER_IMAGE) \
		build -var jag_build_directory=/source/build -var build_id=${SEM_VER} build/package/packer/packer-template.json
	$(call run,./build/update_artifacts_json.sh,$(ARTIFACT_BLANK),packer-manifest.json)

all: jag-config docker-images packer

publish: publish-docker-images publish-helm-chart packer

docker-compose: jag-cp jag-telemetry jag-authz
	docker-compose down
	docker-compose build
	docker-compose up