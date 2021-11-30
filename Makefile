MAKEFLAGS += --silent

PROJECTNAME=tagsToEnvVars

.DEFAULT_GOAL := tagsToEnvVars

SRC_DIR := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
BUILD_DIR := $(SRC_DIR)build
OUTPUT_DIR := $(SRC_DIR)build/output
CACHE_DIR := $(SRC_DIR)build/output/.cache
ARTIFACTS_FILE := $(SRC_DIR)build/output/artifacts.json

BUILD_IMAGE := docker-hub-remote.dr.corp.adobe.com/golang:1.17
UID := $(shell id -u)
GID := $(shell id -g)
GOOS := linux
GOARCH := amd64
VERSION := 0.0.2
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

DOCKER_RUN_ARGS := --rm -w /source --mount type=bind,source=$(SRC_DIR),target=/source -e CGO_ENABLED=0 -e GOOS=$(GOOS) -e GOARCH=$(GOARCH) -e SEM_VER="$(SEM_VER)" -e BUILD_TIMESTAMP="$(BUILD_TIMESTAMP)" -e BUILD_NUMBER="$(BUILD_NUMBER)" $(BUILD_IMAGE)

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

version:
	echo "$(SEM_VER)"

clean:
	echo "Cleaning..."
	rm -Rf $(OUTPUT_DIR)

build-shell:
	echo "Starting a build env shell..."
	docker run -it $(DOCKER_RUN_ARGS) /bin/bash

unit-tests:
	echo "Running tests"
	$(call run,./build/run_tests.sh)

cmds: $(CMDS)

%: cmd/%/main.go unit-tests
	echo "Building $*"
	$(call run,./build/run_cmd_build.sh,$*)

tagsToEnvVars:
	echo "Building....."
	docker run -it $(DOCKER_RUN_ARGS) go build .

all: tagsToEnvVars
