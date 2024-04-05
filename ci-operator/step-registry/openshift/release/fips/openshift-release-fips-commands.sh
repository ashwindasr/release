#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

function run_command() {
    local CMD="$1"
    echo "Running Command: ${CMD}"
    eval "${CMD}"
}

run_command "oc whoami"
run_command "oc version -o yaml"
pass=true

# get a master node
master_node_0=$(oc get node -l node-role.kubernetes.io/master= --no-headers | grep -Ev "NotReady|SchedulingDisabled"| awk '{print $1}' | awk 'NR==1{print}')
if [[ -z $master_node_0 ]]; then
    echo "Error master node0 name is null!"
    pass=false
fi
# create a ns
project="fips-scan-payload-$RANDOM"
run_command "oc new-project $project --skip-config-write"
if [ $? == 0 ]; then
    echo "create $project project successfully"
else
    echo "Fail to create $project project."
    pass=false
fi

# check whether it is disconnected cluster
oc label namespace "$project" security.openshift.io/scc.podSecurityLabelSync=false pod-security.kubernetes.io/enforce=privileged pod-security.kubernetes.io/audit=privileged pod-security.kubernetes.io/warn=privileged --overwrite=true || true
cluster_http_proxy=$(oc get proxy cluster -o=jsonpath='{.spec.httpProxy}')
cluster_https_proxy=$(oc get proxy cluster -o=jsonpath='{.spec.httpProxy}')
attempt=0
while true; do
    out=$(oc --request-timeout=60s -n "$project" debug node/"$master_node_0" -- chroot /host bash -c "export http_proxy=$cluster_http_proxy; export https_proxy=$cluster_https_proxy; curl -sSI ifconfig.me --connect-timeout 5" 2> /dev/null || true)
    if [[ $out == *"Via: 1.1"* ]]; then
        echo "This is not a disconnected cluster"
        break
    fi
    attempt=$(( attempt + 1 ))
    if [[ $attempt -gt 3 ]]; then
        echo "This is a disconnected cluster, skip testing"
        oc delete ns "$project"
        exit 0
    fi
    sleep 5
done

payload_url="${RELEASE_IMAGE_LATEST}"

if [[ "$payload_url" == *"@sha256"* ]]; then
    payload_url=$(echo "$payload_url" | sed 's/@sha256.*/:latest/')
fi

# run node scan and check the result
report="/tmp/fips-check-payload-scan.log"
oc --request-timeout=300s -n "$project" debug node/"$master_node_0" -- chroot /host bash -c "export http_proxy=$cluster_http_proxy; export https_proxy=$cluster_https_proxy; podman run --authfile /var/lib/kubelet/config.json --privileged -i -v /:/myroot registry.ci.openshift.org/ci/check-payload:latest scan payload -V $MAJOR_MINOR --url $payload_url --root  /myroot &> $report" || true
out=$(oc --request-timeout=300s -n "$project" debug node/"$master_node_0" -- chroot /host bash -c "cat /$report" || true)
echo "The report is: $out"
oc delete ns $project || true
res=$(echo "$out" | grep -E 'Failure Report|Successful run with warnings|Warning Report' || true)
echo "The result is: $res"
if [[ -n $res ]];then
    echo "The result is: $res"
    pass=false
fi

if $pass; then
    exit 0
else
    exit 1
fi
