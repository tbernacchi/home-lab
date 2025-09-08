# CloudNative-PG Setup

## 🐘 PostgreSQL Cluster on Kubernetes

This directory contains the configuration for deploying a PostgreSQL cluster using CloudNative-PG on Kubernetes.

## 📁 Files

- `000-local-path-patch.yaml` - Local-path provisioner configuration update
- `001-storageclass.yaml` - Custom storage class for PostgreSQL
- `002-postgresql-cluster.yaml` - PostgreSQL cluster configuration
- `003-pooler.yaml` - PgBouncer connection pooler configuration

## 🚀 Installation

### 1. Install CloudNative-PG Operator

```bash
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.27/releases/cnpg-1.27.0.yaml
```

### 2. Wait for Operator to be Ready

```bash
kubectl rollout status deployment \
  -n cnpg-system cnpg-controller-manager
```

### 3. Create Storage Directory (on each node)

```bash
# SSH to each node and create the directory
sudo mkdir -p /opt/local-path-provisioner/cnpg
sudo chown -R 1000:1000 /opt/local-path-provisioner/cnpg
```

### 4. Update Local-Path ConfigMap

```bash
# Update the local-path provisioner to recognize our custom path
kubectl apply -f 000-local-path-patch.yaml
```

### 5. Deploy Storage Class

```bash
kubectl apply -f 001-storageclass.yaml
```

### 6. Deploy PostgreSQL Cluster

```bash
kubectl apply -f 002-postgresql-cluster.yaml
```

### 7. Deploy PgBouncer Pooler

```bash
kubectl apply -f 003-pooler.yaml
```

## 🎯 Cluster Configuration

- **Instances**: 3 PostgreSQL replicas
- **Storage**: 10Gi per instance (custom storage class)
- **Connection Pooling**: 2 PgBouncer instances
- **Monitoring**: Prometheus PodMonitor enabled
- **Max Connections**: 100 per instance (300 total)
- **Client Connections**: 1000 via PgBouncer
- **Storage Path**: `/opt/local-path-provisioner/cnpg` on each node

## 📊 Monitoring

The cluster includes Prometheus monitoring with `enablePodMonitor: true`.

## 🔗 Documentation

- [CloudNative-PG Documentation](https://cloudnative-pg.io/documentation/current/installation_upgrade/)
- [CloudNative-PG GitHub](https://github.com/cloudnative-pg/cloudnative-pg)

## 🔗 Connection Strings

### **For Applications:**

```bash
# PgBouncer Pooler (Recommended for production)
postgresql://user:password@cluster-example-pooler.postgres.svc.cluster.local:5432/database

# Read-Write (Primary instance)
postgresql://user:password@cnpg-cluster-rw.postgres.svc.cluster.local:5432/database

# Read-Only (Replica instances)
postgresql://user:password@cnpg-cluster-ro.postgres.svc.cluster.local:5432/database

# Read (Alias for read-only)
postgresql://user:password@cnpg-cluster-r.postgres.svc.cluster.local:5432/database
```

### **Service Types:**
- **`cluster-example-pooler`**: PgBouncer connection pooling (1000 clients → 25 DB connections)
- **`cnpg-cluster-rw`**: Primary instance (read-write)
- **`cnpg-cluster-ro`**: Replica instances (read-only)
- **`cnpg-cluster-r`**: Alias for read-only (compatibility)

## 🛠️ Useful Commands

```bash
# Check cluster status
kubectl get clusters -n postgres

# Check pods
kubectl get pods -n postgres

# Check services
kubectl get svc -n postgres

# Check pooler
kubectl get pooler -n postgres

# Check PodMonitor
kubectl get podmonitor -n postgres

# Connect to database
kubectl exec -it cnpg-cluster-1 -n postgres -- psql -U postgres
```
