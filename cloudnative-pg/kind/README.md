# CloudNative-PG no Kind

Configuração mínima: 1 instância PostgreSQL no Kind.

## Pré-requisitos

- Cluster Kind criado

## 1. Instalar o operator (CRDs + controller)

Obrigatório antes de aplicar o cluster.

```bash
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.28/releases/cnpg-1.28.1.yaml
```

```bash
kubectl rollout status deployment -n cnpg-system cnpg-controller-manager
```

## 2. Deploy do cluster

```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-postgresql-cluster.yaml
```

```bash
kubectl -n postgres get cluster
```

## Conexão

- **Host:** `cnpg-metabase-rw.postgres.svc`
- **Port:** `5432`
- **Database:** `app`
- **User:** `app`
- **Password:** `kubectl -n postgres get secret cnpg-metabase-app -o jsonpath='{.data.password}' | base64 -d`

## Storage

O Kind costuma ter StorageClass `standard`. Se os PVCs ficarem em Pending, instale o local-path-provisioner ou ajuste `storageClass` em `01-postgresql-cluster.yaml`.
