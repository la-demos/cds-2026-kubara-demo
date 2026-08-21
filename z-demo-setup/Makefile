KIND_DEMO_CONFIG ?= config/kind-demo.yaml
HUB_KUBECONFIG ?= ../.local/kind.kubeconfig
MERGED_KUBECONFIG ?= $(HOME)/.kube/config
HUB_CONTEXT ?= kind-hub
OPENBAO_NAMESPACE ?= openbao
OPENBAO_MOUNT ?= kv
PLATFORM_CONFIG ?= ../config.yaml

.PHONY: help kind-up kind-recreate kind-down kind-plan kind-status openbao-secrets

help:
	@printf '%s\n' \
	  'make kind-up            Create both spoke clusters' \
	  'make kind-recreate      Recreate both spoke clusters' \
	  'make kind-down          Delete both spoke clusters' \
	  'make kind-plan          Print the create commands' \
	  'make kind-status        Show contexts and cluster nodes' \
	  'make openbao-secrets    Publish both internal kubeconfigs to OpenBao'

kind-up:
	./scripts/create-kind-demo.sh --config "$(KIND_DEMO_CONFIG)" --hub-kubeconfig "$(HUB_KUBECONFIG)" --merged-kubeconfig "$(MERGED_KUBECONFIG)" --hub-context "$(HUB_CONTEXT)"

kind-recreate:
	./scripts/create-kind-demo.sh --config "$(KIND_DEMO_CONFIG)" --hub-kubeconfig "$(HUB_KUBECONFIG)" --merged-kubeconfig "$(MERGED_KUBECONFIG)" --hub-context "$(HUB_CONTEXT)" --recreate

kind-down:
	./scripts/delete-kind-demo.sh --config "$(KIND_DEMO_CONFIG)"

kind-plan:
	./scripts/create-kind-demo.sh --config "$(KIND_DEMO_CONFIG)" --hub-kubeconfig "$(HUB_KUBECONFIG)" --merged-kubeconfig "$(MERGED_KUBECONFIG)" --hub-context "$(HUB_CONTEXT)" --dry-run

kind-status:
	@./scripts/kind-demo-status.sh --config "$(KIND_DEMO_CONFIG)"

openbao-secrets:
	./scripts/publish-openbao-spokes.sh \
		--config "$(KIND_DEMO_CONFIG)" \
		--hub-kubeconfig "$(HUB_KUBECONFIG)" \
		--namespace "$(OPENBAO_NAMESPACE)" \
		--mount "$(OPENBAO_MOUNT)" \
		--kubara-config "$(PLATFORM_CONFIG)"
