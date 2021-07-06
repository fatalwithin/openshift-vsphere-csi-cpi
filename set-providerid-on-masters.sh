#!/bin/bash
# export your auth config here w/cluster admin rights
export KUBECONFIG=/home/ocpinstall/ocp-upi-install/auth/kubeconfig
# login with your cluster admin
oc login -u cluster_admin -p <yourPassword>
export GOVC_USERNAME='administrator@vsphere.local'
export GOVC_INSECURE=1
export GOVC_PASSWORD='<yourPassword>'
export GOVC_URL='<vcenterIP-FQDN>'
DATACENTER='DatacenterB'
VM_PREFIX='ocp4-master'
IFS=$'\n'
for vm in $(govc ls "/$DATACENTER/vm" | grep $VM_PREFIX); do
    MACHINE_INFO=$(govc vm.info -json -dc=$DATACENTER -vm.ipath="/$vm" -e=true)
    VM_NAME=$(jq -r ' .VirtualMachines[] | .Name' <<< $MACHINE_INFO | awk '{print tolower($0)}')
    # UUIDs come in lowercase, upper case them
    VM_UUID=$( jq -r ' .VirtualMachines[] | .Config.Uuid' <<< $MACHINE_INFO | awk '{print toupper($0)}')
    echo "Patching $VM_NAME with UUID:$VM_UUID"
    oc patch node $VM_NAME -p "{\"spec\":{\"providerID\":\"vsphere://$VM_UUID\"}}"
done
