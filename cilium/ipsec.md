### Ipsec

```
PSK=($(dd if=/dev/urandom count=20 bs=1 2> /dev/null | xxd -p -c 64))
echo $PSK
```

```
kubectl create -n kube-system secret generic cilium-ipsec-keys \
    --from-literal=keys="3+ rfc4106(gcm(aes)) $PSK 128"
```

```
SECRET="$(kubectl get secrets cilium-ipsec-keys -o jsonpath='{.data}' -n kube-system | jq -r ".keys")"
echo $SECRET | base64 --decode
```

```
cilium install --version v1.17.4 \
  --set ipam.mode=cluster-pool \
  --set encryption.enabled=true \
  --set encryption.type=ipsec
```

```
cilium config view | grep enable-ipsec
```