#!/bin/sh

set -e

# Set your environment variables here
ACS_OPERATOR_NAMESPACE=rhacs-operator
ACS_NAMESPACE=stackrox
SECURED_CLUSTER_NAME=hub-cluster


#############################
## Do not modify anything from this line
#############################

# Print environment variables
echo -e "\n=============="
echo -e "ENVIRONMENT VARIABLES:"
echo -e " * ACS_OPERATOR_NAMESPACE: $ACS_OPERATOR_NAMESPACE"
echo -e " * ACS_NAMESPACE: $ACS_NAMESPACE"
echo -e " * SECURED_CLUSTER_NAME: $SECURED_CLUSTER_NAME"
echo -e "==============\n"

# Check if the user is logged in 
if ! oc whoami &> /dev/null; then
    echo -e "Check. You are not logged. Please log in and run the script again."
    exit 1
else
    echo -e "Check. You are correctly logged in. Continue..."
    if ! oc project &> /dev/null; then
        echo -e "Current project does not exist, moving to project Default."
        oc project default 
    fi
fi

# 1) Deploy the ACS operator
echo -e "\n[1/4]Deploying the ACS operator"
oc process -f openshift/00-operator.yaml \
    -p ACS_OPERATOR_NAMESPACE=$ACS_OPERATOR_NAMESPACE | oc apply -f -

echo ""
echo -n "Waiting for Operator pods ready..."
while [[ $(oc get pods -l app=rhacs-operator -n $ACS_OPERATOR_NAMESPACE -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"


# 2) Deploy the ACS Central
echo -e "\n[2/4]Deploying the ACS Central"
oc process -f openshift/10-acs-central.yaml \
    -p ACS_NAMESPACE=$ACS_NAMESPACE | oc apply -f -

echo -n "Waiting for Central pod ready..."
while [[ $(oc get pods -l app=central -n $ACS_NAMESPACE -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"


# 3) Deploy the ACS secrets on the cluster
echo -e "\n[3/4]Deploying the ACS Secured Cluster"
ROX_CENTRAL_ADDRESS=$(oc get routes central -n $ACS_NAMESPACE --template='https://{{ .spec.host }}:443')
ACS_ADMIN_PASSWORD=$(oc get secrets central-htpasswd -n $ACS_NAMESPACE -o go-template --template='{{ index .data "password" | base64decode}}')

roxctl central whoami -e $ROX_CENTRAL_ADDRESS -p $ACS_ADMIN_PASSWORD

roxctl -e $ROX_CENTRAL_ADDRESS -p $ACS_ADMIN_PASSWORD \
  central init-bundles generate $SECURED_CLUSTER_NAME \
  --insecure-skip-tls-verify \
  --output-secrets cluster_init_bundle.yaml

oc apply -f cluster_init_bundle.yaml -n $ACS_NAMESPACE


# 4) Deploy the ACS Secured Cluster
echo -e "\n[4/4]Deploying the ACS Secured Cluster"
oc process -f openshift/20-securedcluster.yaml \
    -p ACS_NAMESPACE=$ACS_NAMESPACE \
    -p SECURED_CLUSTER_NAME=$SECURED_CLUSTER_NAME | oc apply -f -

# echo -n "Waiting for Secured Cluster pod ready..."
# while [[ $(oc get pods -l app=central -n $ACS_NAMESPACE -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"

oc wait --for=condition=Deployed securedcluster stackrox-secured-cluster-$SECURED_CLUSTER_NAME -n $ACS_NAMESPACE

echo -e "\nURLS:"
echo -e " * ACS: $ROX_CENTRAL_ADDRESS"
echo -e " * User: admin"
echo -e " * Pass: $ACS_ADMIN_PASSWORD"

