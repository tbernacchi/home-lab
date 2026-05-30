# Clean Raspberry Pi Node

Steps to fully clean a Raspberry Pi node before reinstalling K3s.

## 1. Backup /root

Run from your local machine:

```bash
cd raspberry-bkp
./backup-root.sh <node-ip>
# Output: raspberry-bkp/backups/raspberrypi4-1.tar.gz
```

## 2. Copy reset script to node

```bash
scp reset-k3s-cluster.sh tadeu@<node-ip>:~/
```

## 3. Uninstall K3s

```bash
ssh tadeu@<node-ip> "sudo ./reset-k3s-cluster.sh --uninstall-only"
```

## 4. Remove containerd (if installed manually)

```bash
systemctl stop containerd
systemctl disable containerd
rm /usr/local/bin/containerd
find /etc/systemd/system -name "containerd*" -delete
systemctl daemon-reload
```

## 5. Remove broken kernel packages

Check running kernel (must be raspi, not generic):

```bash
uname -r
# Expected: 6.5.0-1013-raspi (or similar raspi kernel)
```

Remove broken generic kernel if present:

```bash
dpkg --purge --force-remove-reinstreq linux-image-unsigned-6.9.3-060903-generic
rm -rf /lib/modules/6.9.3-060903-generic
apt-get -f install
```

## 6. Reinstall K3s

```bash
sudo ./reset-k3s-cluster.sh --version latest --node-ip <node-ip>
```

Join workers after master is up:

```bash
sudo ./reset-and-join-node.sh --version <version> --master-ip <master-ip> --token <token>
```

Get token from master:

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```
