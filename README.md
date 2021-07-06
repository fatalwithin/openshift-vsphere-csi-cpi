## Preface

This is a fixed version of the solution published on https://access.redhat.com/solutions/5900501

## Issue

The vSphere CSI installation method for native Kubernetes can be found in Kubernetes [vSphere Cloud Provider](https://cloud-provider-vsphere.sigs.k8s.io/).
Kubernetes Container Storage Interface, or CSI, provides an interface for exposing arbitrary block and file storage systems to containerized workloads in Kubernetes.

While the framework exists in upstream Kubernetes, the storage provider is in charge of their own drivers. This means timely updates can be included in the platform itself and not in Kubernetes. This article will explain the process of installing and configuring CSI for vSphere and will discuss some of the benefits of migrating to CSI vs. the in-tree vSphere Storage for Kubernetes.

## Resolution

1) First, taint all the nodes for CPI install with the following command:

```bash
oc adm taint nodes --selector='!node-role.kubernetes.io/master' node.cloudprovider.kubernetes.io/uninitialized=true:NoSchedule
```

2) Get the `vsphere.conf` and `cpi-global-secret.yaml` files for CPI.

3) Create the configmap and secret in OpenShift Container Platform for CPI.

```bash
oc create configmap cloud-config --from-file=/home/ocpinstall/ocp-upi-install/vsphere.conf --
namespace=kube-system

oc create -f /home/ocpinstall/ocp-upi-install/cpi-global-secret.yaml
```

4) Create the YAML files for roles/rolebindings for CPI. (`cpi-roles.yaml`, `cpi-rolebindings.yaml` )

5) Create the clusterroles, clusterrolebindings, service account privileges, and CPI daemonset.

```bash
oc create -f /home/ocpinstall/ocp-upi-install/cpi-roles.yaml
oc create -f /home/ocpinstall/ocp-upi-install/cpi-role-bindings.yaml
oc adm policy add-scc-to-user privileged -z cloud-controller-manager
oc create -f /home/ocpinstall/ocp-upi-install/cpi-daemonset.yaml
```

6) Set the ProviderID on the master nodes manually in the case it is not running with `cloud-provider=vsphere`.

```bash
chmod 777 script.sh
./script.sh
```

7) Create the vsphere.conf, RBAC, deployment, and daemonset YAML (CSI).

8) Finally, create the secret, RBAC, service account privileges, and CSI deployment, and daemonset.

```bash
oc create secret generic vsphere-config-secret --from-file=/home/ocpinstall/ocp-upi-install/csivsphere.conf --namespace=kube-system
oc create -f /home/ocpinstall/ocp-upi-install/csi-rbac.yaml
oc adm policy add-scc-to-user privileged -z vsphere-csi-controller
oc create -f /home/ocpinstall/ocp-upi-install/csi-controller-deploy.yaml
oc create -f /home/ocpinstall/ocp-upi-install/csi-daemonset.yaml
```

This completes the vSphere CPI/CSI installation on Red Hat OpenShift Container Platform.

## Diagnostic Steps

The required platform for vSphere CSI is at least vSphere 6.7 U3. This particular update includes vSphere’s Cloud Native Storage, which provides ease of use in the vCenter console.

Additionally, cluster VMs will need “disk.enableUUID” and VM hardware version 15 or higher.

```bash
# govc find / -type m -runtime.powerState poweredOn -name 'ocp-*' | xargs -L 1 govc vm.power -off $1

# govc find / -type m -runtime.powerState poweredOff -name 'ocp-*' | xargs -L 1 govc vm.change -e="disk.enableUUID=1" -vm $1

# govc find / -type m -runtime.powerState poweredOff -name 'ocp-*' | xargs -L 1 govc vm.upgrade -version=15 -vm $1

# govc find / -type m -runtime.powerState poweredOff -name 'demo-*' | grep -v rhcos | xargs -L 1 govc vm.power -on $1
```

The secret will be used for CSI’s configuration and access to the vCenter API.

```bash
It is important to note that the cluster-id in the below must be different per cluster, or volumes will end up being mounted into the wrong OCP cluster.

# vim csi-vsphere.conf

[Global]
cluster-id = "csi-vsphere-cluster"
[VirtualCenter "vcsa67.cloud.example.com"]
insecure-flag = "true"
user = "Administrator@vsphere.local"
password = "SuperPassword"
port = "443"
datacenters = "RDU"

# oc create secret generic vsphere-config-secret --from-file=csi-vsphere.conf --namespace=kube-system
# oc get secret vsphere-config-secret --namespace=kube-system
NAME                    TYPE     DATA    AGE
vsphere-config-secret   Opaque   1      43s
```

After the installation, verify success by querying one of the new custom resource definitions:

```bash
# oc get  CSINode
NAME              CREATED AT
control-plane-0   2021-03-02T18:21:44Z
```

The storage class should be deployed and tested. In the event that the vSphere cloud provider storage class was also present, the additional storage class can be created then used for migrations and workload use in tandem.

```bash
# oc get sc
NAME             PROVISIONER                    AGE
csi-sc           csi.vsphere.vmware.com         6m44s
thin (default)   kubernetes.io/vsphere-volume   3h29m

# vi csi-sc.yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: csi-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: csi.vsphere.vmware.com
parameters:
  StoragePolicyName: "GoldVM"

# oc create -f csi-sc.yaml

# Test the new storage class
# vi csi-pvc.yaml 
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: csi-pvc2
  annotations:
    volume.beta.kubernetes.io/storage-class: csi-sc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 30Gi

# oc create -f csi-pvc.yaml

# oc get pvc
NAME       STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
csi-pvc2   Bound    pvc-8892e718-d89a-4267-9826-e2beb362e723   30Gi       RWO            csi-sc         9m27s
```

In the event that the new CSI storage class is the preferred one, patch both of the classes:

```bash
# oc patch storageclass thin -p '{"metadata": {"annotations": \
    {"storageclass.kubernetes.io/is-default-class": "false"}}}'
# oc patch storageclass csi-sc -p '{"metadata": {"annotations": \
    {"storageclass.kubernetes.io/is-default-class": "true"}}}'
```

