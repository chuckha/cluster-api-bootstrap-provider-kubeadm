# Copyright 2019 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# If you update this file, please follow:
# https://suva.sh/posts/well-documented-makefiles/

.DEFAULT_GOAL:=help

# Use GOPROXY environment variable if set
GOPROXY := $(shell go env GOPROXY)
ifeq ($(GOPROXY),)
GOPROXY := https://proxy.golang.org
endif
export GOPROXY

REGISTRY ?= gcr.io/$(shell gcloud config get-value project)
# A release does not need to define this
MANAGER_IMAGE_NAME ?= cluster-api-bootstrap-provider-kubeadm
MANAGER_IMAGE_TAG ?= dev
PULL_POLICY ?= Always

# Used in docker-* targets.
MANAGER_IMAGE ?= $(REGISTRY)/$(MANAGER_IMAGE_NAME):$(MANAGER_IMAGE_TAG)

# Produce CRDs that work back to Kubernetes 1.11 (no version conversion)
CRD_OPTIONS ?= "crd:trivialVersions=true"

TOOLS_DIR := hack/tools
CONTROLLER_GEN_BIN := bin/controller-gen
CONTROLLER_GEN := $(TOOLS_DIR)/$(CONTROLLER_GEN_BIN)

# Allow overriding manifest generation destination directory
MANIFEST_ROOT ?= "config"
CRD_ROOT ?= "$(MANIFEST_ROOT)/crd/bases"
WEBHOOK_ROOT ?= "$(MANIFEST_ROOT)/webhook"
RBAC_ROOT ?= "$(MANIFEST_ROOT)/rbac"

# Active module mode, as we use go modules to manage dependencies
export GO111MODULE=on

.PHONY: all
all: manager

help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: test
test: generate fmt vet ## Run tests
	go test ./api/... ./certs/... ./controllers/... -coverprofile cover.out

.PHONY: manager
manager: generate fmt vet ## Build manager binary
	go build -o bin/manager main.go

.PHONY: run
run: generate fmt vet ## Run against the configured Kubernetes cluster in ~/.kube/config
	go run ./main.go

.PHONY: install
install: generate ## Install CRDs into a cluster
	kubectl apply -f config/crd/bases

.PHONY: deploy
deploy: generate ## Deploy controller in the configured Kubernetes cluster in ~/.kube/config
	kubectl apply -f config/crd/bases
	kubectl kustomize config/default | kubectl apply -f -

.PHONY: fmt
fmt: ## Run go fmt against code
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code
	go vet ./...

.PHONY: mod
mod:
	go mod download

# Generate code
.PHONY: generate
generate: $(CONTROLLER_GEN) ## Generate code
	$(MAKE) generate-manifests
	$(MAKE) generate-deepcopy

.PHONY: generate-deepcopy
generate-deepcopy: $(CONTROLLER_GEN) ## Generate deepcopy files.
	$(CONTROLLER_GEN) object:headerFile=./hack/boilerplate/boilerplate.generatego.txt paths=./api/...

.PHONY: generate-manifests
generate-manifests: $(CONTROLLER_GEN) ## Generate manifests e.g. CRD, RBAC etc.
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./..." output:crd:dir=$(CRD_ROOT) output:webhook:dir=$(WEBHOOK_ROOT) output:rbac:dir=$(RBAC_ROOT)

.PHONY: docker-build
docker-build: test ## Build the docker image
	docker build . -t ${MANAGER_IMAGE}
	@echo "updating kustomize image patch file for manager resource"
	sed -i'' -e 's@image: .*@image: '"${MANAGER_IMAGE}"'@' ./config/default/manager_image_patch.yaml

.PHONY: docker-push
docker-push: ## Push the docker image
	docker push ${MANAGER_IMAGE}

# Build controller-gen
$(CONTROLLER_GEN): $(TOOLS_DIR)/go.mod
	cd $(TOOLS_DIR) && go build -o $(CONTROLLER_GEN_BIN) sigs.k8s.io/controller-tools/cmd/controller-gen
