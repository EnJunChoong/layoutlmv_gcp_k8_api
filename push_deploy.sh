#!/bin/bash
set -euxo

export IMAGE_NAME="layoutlmv2"
export IMAGE_TAG="v1-1"
export LOCATION="asia-southeast1-docker.pkg.dev"
export REGISTRY="$LOCATION/manulife-assessment/manulife-assessment-container-registry"
export IMAGE_PATH="$REGISTRY/$IMAGE_NAME:$IMAGE_TAG"

gcloud auth configure-docker asia-southeast1-docker.pkg.dev 
docker build -t $IMAGE_NAME ./app/
docker tag $IMAGE_NAME $IMAGE_PATH
docker push $IMAGE_PATH


# Register secret key to gke cluster
kubectl apply -f kubectl_configs/secrets.yaml # file excluded from git
# Deploy app to gke cluster
envsubst < kubectl_configs/layoutlmv2_deployment.yaml | kubectl apply -f -
# Setup horizontal pod autoscaler
envsubst < kubectl_configs/layoutlmv2_hpa.yaml | kubectl apply -f -
# Create service with external load balancer
envsubst < kubectl_configs/layoutlmv2_extlb_svc.yaml | kubectl apply -f -



# # If using GPU, need to install nvidia on daemon
# kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded.yaml
