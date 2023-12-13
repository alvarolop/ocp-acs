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
ACS_ROUTE=$(oc get routes central -n $ACS_NAMESPACE --template='https://{{ .spec.host }}')
roxctl central login -e $ACS_ROUTE # | grep "Access token:"  | sed -n 's/^INFO:  Access token: //p'

read -p 'Copy here the Access token: ' ACCESS_TOKEN

export ROX_API_TOKEN=$ACCESS_TOKEN
ROX_CENTRAL_ADDRESS="$ACS_ROUTE:443"

roxctl -e $ROX_CENTRAL_ADDRESS \
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




ACS_PASS=$(oc -n $ACS_NAMESPACE get secret central-htpasswd -o go-template='{{index .data "password" | base64decode}}')

echo -e "\nURLS:"
echo -e " * ACS: $ACS_ROUTE"
echo -e " * User: admin"
echo -e " * Pass: $ACS_PASS"

