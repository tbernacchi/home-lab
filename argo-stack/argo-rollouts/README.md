# Argo Rollouts

This directory contains the Argo Rollouts configuration and patch files.

## Files

- `kustomization.yaml` - Kustomize configuration
- `rollout-demo.yaml` - Demo rollout configuration
- `patch-argocd-server.yaml` - Patch file to enable Argo Rollouts extension in Argo CD UI

## Usage

To enable the Argo Rollouts extension in the Argo CD UI, apply the patch:

```bash
kubectl patch deployment argocd-server -n argocd --patch "$(cat argo-stack/argo-rollouts/patch-argocd-server.yaml)"
```

This patch adds the rollout extension to the Argo CD server deployment, allowing you to view and manage rollouts directly from the Argo CD UI.

## Reference

- [Argo Rollouts Demo](https://github.com/argoproj/rollouts-demo)
- [Rollout Extension](https://github.com/argoproj-labs/rollout-extension)