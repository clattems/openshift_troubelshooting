#!/bin/bash

# OpenShift Service Mesh 3.0 - Bookinfo Application Lab Setup
# Prerequisites: Service Mesh Operator already installed
# OpenShift 4.19+ with Service Mesh 3.0

set -e

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_check() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

# Cleanup function
cleanup_lab() {
    log_warn "Starting cleanup of Bookinfo lab..."
    
    read -p "This will delete the bookinfo, istio-system, and istio-cni projects. Continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled"
        return 0
    fi
    
    log_info "Deleting bookinfo project..."
    oc delete project bookinfo --ignore-not-found=true
    
    log_info "Deleting Istio resources..."
    oc delete istio default -n istio-system --ignore-not-found=true
    
    log_info "Deleting istio-system project..."
    oc delete project istio-system --ignore-not-found=true
    
    log_info "Deleting IstioCNI resources..."
    oc delete istiocni default -n istio-cni --ignore-not-found=true
    
    log_info "Deleting istio-cni project..."
    oc delete project istio-cni --ignore-not-found=true
    
    log_info "Cleanup complete!"
}

# Check prerequisites
check_prerequisites() {
    log_check "Checking prerequisites..."
    
    # Check if oc command is available
    if ! command -v oc &> /dev/null; then
        log_error "OpenShift CLI (oc) not found. Please install it first."
        exit 1
    fi
    log_info "✓ OpenShift CLI found"
    
    # Check if logged in to OpenShift
    if ! oc whoami &> /dev/null; then
        log_error "Not logged in to OpenShift. Please run 'oc login' first."
        exit 1
    fi
    log_info "✓ Logged in as $(oc whoami)"
    
    # Check cluster version
    CLUSTER_VERSION=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown")
    log_info "✓ Cluster version: $CLUSTER_VERSION"
    
    # Check if Service Mesh Operator is installed
    log_info "Checking for Service Mesh Operator..."
    
    # Check for Service Mesh 3 operator
    SM3_INSTALLED=$(oc get csv -n openshift-operators 2>/dev/null | grep "servicemeshoperator3" | wc -l)
    SM2_INSTALLED=$(oc get csv -n openshift-operators 2>/dev/null | grep "servicemeshoperator.v2" | wc -l)
    
    if [ "$SM3_INSTALLED" -eq 0 ]; then
        log_error "Red Hat OpenShift Service Mesh 3 Operator not found"
        if [ "$SM2_INSTALLED" -gt 0 ]; then
            log_error "Service Mesh 2 is installed, but this script requires Service Mesh 3"
            log_error "You have these operators installed:"
            oc get csv -n openshift-operators | grep servicemesh
            log_error ""
            log_error "To use Service Mesh 3:"
            log_error "1. Install 'Red Hat OpenShift Service Mesh 3' from OperatorHub"
            log_error "2. Or modify this script to use Service Mesh 2 APIs"
        else
            log_error "Please install the Red Hat OpenShift Service Mesh 3 Operator first"
            log_error "You can install it from: Operators -> OperatorHub -> Red Hat OpenShift Service Mesh"
        fi
        exit 1
    fi
    
    # Get operator status for Service Mesh 3
    OPERATOR_STATUS=$(oc get csv -n openshift-operators -o jsonpath='{.items[?(@.metadata.name~"servicemeshoperator3")].status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$OPERATOR_STATUS" != "Succeeded" ]; then
        log_error "Service Mesh 3 Operator status is '$OPERATOR_STATUS', expected 'Succeeded'"
        log_error "Wait for the operator to finish installing"
        oc get csv -n openshift-operators | grep servicemesh
        exit 1
    fi
    log_info "✓ Service Mesh 3 Operator is installed and ready"
    
    # Warn if both SM2 and SM3 are installed
    if [ "$SM2_INSTALLED" -gt 0 ]; then
        log_warn "Both Service Mesh 2 and 3 operators are installed"
        log_warn "This can cause conflicts. Consider uninstalling Service Mesh 2"
        log_warn "Continuing with Service Mesh 3..."
    fi
    
    # Check for required CRDs
    log_info "Checking for Istio CRDs..."
    if ! oc get crd istios.sailoperator.io &> /dev/null; then
        log_error "Istio CRD (istios.sailoperator.io) not found"
        log_error "The Service Mesh Operator may still be installing"
        log_error "Wait a few minutes and try again, or check operator status:"
        log_error "  oc get csv -n openshift-operators"
        log_error "  oc get pods -n openshift-operators"
        exit 1
    fi
    log_info "✓ Istio CRDs are installed"
    
    if ! oc get crd istiocnis.sailoperator.io &> /dev/null; then
        log_error "IstioCNI CRD (istiocnis.sailoperator.io) not found"
        log_error "The Service Mesh Operator may still be installing"
        exit 1
    fi
    log_info "✓ IstioCNI CRDs are installed"
    
    # Check user permissions
    if ! oc auth can-i create project &> /dev/null; then
        log_error "Insufficient permissions. You need cluster-admin or project creation rights."
        exit 1
    fi
    log_info "✓ User has sufficient permissions"
    
    echo ""
}

# Verify Istio control plane
verify_istio_control_plane() {
    log_check "Verifying Istio control plane..."
    
    # Check if Istio resource exists
    if ! oc get istio default -n istio-system &> /dev/null; then
        log_error "Istio resource 'default' not found in istio-system namespace"
        return 1
    fi
    
    # Check Istio status
    ISTIO_STATUS=$(oc get istio default -n istio-system -o jsonpath='{.status.state}' 2>/dev/null)
    if [ "$ISTIO_STATUS" != "Healthy" ]; then
        log_error "Istio status is '$ISTIO_STATUS', expected 'Healthy'"
        oc get istio default -n istio-system -o yaml
        return 1
    fi
    log_info "✓ Istio control plane is Healthy"
    
    # Check istiod pods
    if ! oc get pods -n istio-system -l app=istiod &> /dev/null; then
        log_error "No istiod pods found"
        return 1
    fi
    
    ISTIOD_READY=$(oc get pods -n istio-system -l app=istiod -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -c "True" || echo "0")
    if [ "$ISTIOD_READY" -eq 0 ]; then
        log_error "No istiod pods are ready"
        oc get pods -n istio-system -l app=istiod
        return 1
    fi
    log_info "✓ $ISTIOD_READY istiod pod(s) ready"
    
    return 0
}

# Verify Istio CNI
verify_istio_cni() {
    log_check "Verifying Istio CNI..."
    
    # Check if IstioCNI resource exists
    if ! oc get istiocni default -n istio-cni &> /dev/null; then
        log_error "IstioCNI resource 'default' not found in istio-cni namespace"
        return 1
    fi
    
    # Check IstioCNI status
    CNI_STATUS=$(oc get istiocni default -n istio-cni -o jsonpath='{.status.state}' 2>/dev/null)
    if [ "$CNI_STATUS" != "Healthy" ]; then
        log_error "IstioCNI status is '$CNI_STATUS', expected 'Healthy'"
        oc get istiocni default -n istio-cni -o yaml
        return 1
    fi
    log_info "✓ Istio CNI is Healthy"
    
    # Check CNI pods
    CNI_PODS_READY=$(oc get pods -n istio-cni -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -c "True" || echo "0")
    if [ "$CNI_PODS_READY" -eq 0 ]; then
        log_error "No CNI pods are ready"
        oc get pods -n istio-cni
        return 1
    fi
    log_info "✓ $CNI_PODS_READY CNI pod(s) ready"
    
    return 0
}

# Verify bookinfo application
verify_bookinfo_app() {
    log_check "Verifying Bookinfo application..."
    
    # Check expected services
    EXPECTED_SERVICES=("details" "productpage" "ratings" "reviews")
    for service in "${EXPECTED_SERVICES[@]}"; do
        if ! oc get service "$service" -n bookinfo &> /dev/null; then
            log_error "Service '$service' not found"
            return 1
        fi
        log_info "✓ Service '$service' exists"
    done
    
    # Check pods
    TOTAL_PODS=$(oc get pods -n bookinfo --no-headers 2>/dev/null | wc -l)
    if [ "$TOTAL_PODS" -eq 0 ]; then
        log_error "No pods found in bookinfo namespace"
        return 1
    fi
    log_info "✓ Found $TOTAL_PODS pod(s)"
    
    # Check pod readiness and sidecar injection
    PODS_NOT_READY=$(oc get pods -n bookinfo --no-headers 2>/dev/null | grep -v "Running" | wc -l)
    if [ "$PODS_NOT_READY" -gt 0 ]; then
        log_warn "$PODS_NOT_READY pod(s) not in Running state"
        oc get pods -n bookinfo
    fi
    
    # Verify sidecar injection (should have 2 containers per pod)
    PODS_WITHOUT_SIDECAR=$(oc get pods -n bookinfo -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[*].name}{"\n"}{end}' | grep -v "istio-proxy" | wc -l || echo "0")
    if [ "$PODS_WITHOUT_SIDECAR" -gt 0 ]; then
        log_error "Some pods don't have istio-proxy sidecar injected"
        oc get pods -n bookinfo -o jsonpath='{range .items[*]}{.metadata.name}{" containers: "}{.spec.containers[*].name}{"\n"}{end}'
        return 1
    fi
    log_info "✓ All pods have istio-proxy sidecar"
    
    return 0
}

# Verify internal connectivity
verify_internal_connectivity() {
    log_check "Verifying internal application connectivity..."
    
    RATINGS_POD=$(oc get pod -l app=ratings -n bookinfo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -z "$RATINGS_POD" ]; then
        log_error "Could not find ratings pod"
        return 1
    fi
    
    log_info "Testing productpage from ratings pod..."
    if ! oc exec "$RATINGS_POD" -c ratings -n bookinfo -- curl -sS --max-time 10 productpage:9080/productpage | grep -q "<title>"; then
        log_error "Failed to get valid response from productpage"
        return 1
    fi
    log_info "✓ Internal connectivity working"
    
    return 0
}

# Verify gateway
verify_gateway() {
    log_check "Verifying Istio Gateway..."
    
    # Check if gateway exists
    if ! oc get gateway bookinfo-gateway -n bookinfo &> /dev/null; then
        log_error "Gateway 'bookinfo-gateway' not found"
        return 1
    fi
    log_info "✓ Gateway 'bookinfo-gateway' exists"
    
    # Check if virtual service exists
    if ! oc get virtualservice bookinfo -n bookinfo &> /dev/null; then
        log_error "VirtualService 'bookinfo' not found"
        return 1
    fi
    log_info "✓ VirtualService 'bookinfo' exists"
    
    # Check ingress gateway pods
    if ! oc get pods -l app=istio-ingressgateway -n bookinfo &> /dev/null; then
        log_error "No ingress gateway pods found"
        return 1
    fi
    
    GW_PODS_READY=$(oc get pods -l app=istio-ingressgateway -n bookinfo -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -c "True" || echo "0")
    if [ "$GW_PODS_READY" -eq 0 ]; then
        log_error "Ingress gateway pods are not ready"
        oc get pods -l app=istio-ingressgateway -n bookinfo
        return 1
    fi
    log_info "✓ $GW_PODS_READY ingress gateway pod(s) ready"
    
    return 0
}

# Verify route
verify_route() {
    log_check "Verifying OpenShift Route..."
    
    if ! oc get route istio-ingressgateway -n bookinfo &> /dev/null; then
        log_error "Route 'istio-ingressgateway' not found"
        return 1
    fi
    
    HOST=$(oc get route istio-ingressgateway -n bookinfo -o jsonpath='{.spec.host}' 2>/dev/null)
    if [ -z "$HOST" ]; then
        log_error "Could not get route hostname"
        return 1
    fi
    log_info "✓ Route exists: $HOST"
    
    # Test external connectivity
    log_info "Testing external connectivity..."
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${HOST}/productpage" 2>/dev/null || echo "000")
    if [ "$RESPONSE" != "200" ]; then
        log_warn "Route returned HTTP $RESPONSE (expected 200)"
        log_warn "This might be normal if DNS propagation is still in progress"
        log_warn "Try accessing manually: http://${HOST}/productpage"
    else
        log_info "✓ External connectivity working (HTTP 200)"
    fi
    
    return 0
}

# Handle script arguments
if [ "$1" == "cleanup" ] || [ "$1" == "--cleanup" ]; then
    cleanup_lab
    exit 0
fi

if [ "$1" == "verify" ] || [ "$1" == "--verify" ]; then
    log_info "Running verification checks only..."
    check_prerequisites
    verify_istio_control_plane
    verify_istio_cni
    verify_bookinfo_app
    verify_internal_connectivity
    verify_gateway
    verify_route
    log_info "Verification complete!"
    exit 0
fi

# Main setup process
log_info "Starting OpenShift Service Mesh 3.0 Bookinfo Lab Setup"
echo ""

# Check prerequisites
check_prerequisites

# Step 1: Create istio-system project
log_info "Step 1: Creating istio-system project..."
if oc get project istio-system &> /dev/null; then
    log_warn "Project istio-system already exists, skipping creation"
else
    oc new-project istio-system
    log_info "✓ Created istio-system project"
fi
echo ""

# Step 2: Create Istio Control Plane
log_info "Step 2: Deploying Istio Control Plane..."
cat <<EOF | oc apply -f -
apiVersion: sailoperator.io/v1alpha1
kind: Istio
metadata:
  name: default
  namespace: istio-system
spec:
  version: v1.24.6
  namespace: istio-system
EOF

log_info "Waiting for Istio Control Plane to be ready (this may take a few minutes)..."
if ! oc wait --for=condition=Ready istio/default -n istio-system --timeout=300s 2>/dev/null; then
    log_error "Istio Control Plane failed to become ready within 5 minutes"
    log_error "Checking status..."
    oc get istio default -n istio-system -o yaml
    exit 1
fi

# Verify control plane
if ! verify_istio_control_plane; then
    log_error "Istio Control Plane verification failed"
    exit 1
fi
echo ""

# Step 3: Create istio-cni project
log_info "Step 3: Creating istio-cni project..."
if oc get project istio-cni &> /dev/null; then
    log_warn "Project istio-cni already exists, skipping creation"
else
    oc new-project istio-cni
    log_info "✓ Created istio-cni project"
fi
echo ""

# Step 4: Deploy Istio CNI Plugin
log_info "Step 4: Deploying Istio CNI Plugin..."
cat <<EOF | oc apply -f -
apiVersion: sailoperator.io/v1alpha1
kind: IstioCNI
metadata:
  name: default
  namespace: istio-cni
spec:
  version: v1.24.6
  namespace: istio-cni
EOF

log_info "Waiting for Istio CNI to be ready (this may take a few minutes)..."
if ! oc wait --for=condition=Ready istiocni/default -n istio-cni --timeout=300s 2>/dev/null; then
    log_error "Istio CNI failed to become ready within 5 minutes"
    log_error "Checking status..."
    oc get istiocni default -n istio-cni -o yaml
    exit 1
fi

# Verify CNI
if ! verify_istio_cni; then
    log_error "Istio CNI verification failed"
    exit 1
fi
echo ""

# Step 5: Create bookinfo project
log_info "Step 5: Creating bookinfo project..."
if oc get project bookinfo &> /dev/null; then
    log_warn "Project bookinfo already exists, skipping creation"
else
    oc new-project bookinfo
    log_info "✓ Created bookinfo project"
fi
echo ""

# Step 6: Label bookinfo namespace for discovery and injection
log_info "Step 6: Labeling bookinfo namespace..."
oc label namespace bookinfo istio-discovery=enabled istio-injection=enabled --overwrite
log_info "✓ Applied discovery and injection labels"

# Verify labels
LABELS=$(oc get namespace bookinfo --show-labels | grep -o "istio-discovery=enabled.*istio-injection=enabled" || echo "")
if [ -z "$LABELS" ]; then
    log_error "Failed to verify namespace labels"
    oc get namespace bookinfo --show-labels
    exit 1
fi
log_info "✓ Verified namespace labels"
echo ""

# Step 7: Deploy Bookinfo application
log_info "Step 7: Deploying Bookinfo application..."
if ! oc apply -f https://raw.githubusercontent.com/openshift-service-mesh/istio/release-1.24/samples/bookinfo/platform/kube/bookinfo.yaml -n bookinfo; then
    log_error "Failed to deploy Bookinfo application"
    exit 1
fi
log_info "✓ Bookinfo manifests applied"

log_info "Waiting for Bookinfo pods to be ready (this may take a few minutes)..."
sleep 15

# Wait for each deployment to be ready
DEPLOYMENTS=("details-v1" "productpage-v1" "ratings-v1" "reviews-v1" "reviews-v2" "reviews-v3")
for deployment in "${DEPLOYMENTS[@]}"; do
    log_info "Waiting for deployment/$deployment..."
    if ! oc wait --for=condition=Available deployment/$deployment -n bookinfo --timeout=300s 2>/dev/null; then
        log_error "Deployment $deployment failed to become available"
        oc get deployment $deployment -n bookinfo
        oc get pods -l app=${deployment%-v*} -n bookinfo
    fi
done

# Verify bookinfo app
if ! verify_bookinfo_app; then
    log_error "Bookinfo application verification failed"
    exit 1
fi
echo ""

# Step 8: Test internal connectivity
if ! verify_internal_connectivity; then
    log_error "Internal connectivity check failed"
    exit 1
fi
echo ""

# Step 9: Deploy Ingress Gateway
log_info "Step 9: Deploying Istio Ingress Gateway..."
cat <<EOF | oc apply -n bookinfo -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: istio-ingressgateway
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: istio-ingressgateway
spec:
  replicas: 1
  selector:
    matchLabels:
      app: istio-ingressgateway
  template:
    metadata:
      annotations:
        inject.istio.io/templates: gateway
      labels:
        app: istio-ingressgateway
        sidecar.istio.io/inject: "true"
    spec:
      serviceAccountName: istio-ingressgateway
      containers:
      - name: istio-proxy
        image: auto
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 2000m
            memory: 1024Mi
---
apiVersion: v1
kind: Service
metadata:
  name: istio-ingressgateway
spec:
  type: ClusterIP
  selector:
    app: istio-ingressgateway
  ports:
  - name: http
    port: 80
    targetPort: 8080
  - name: https
    port: 443
    targetPort: 8443
EOF

log_info "Waiting for Ingress Gateway to be ready..."
if ! oc wait --for=condition=Available deployment/istio-ingressgateway -n bookinfo --timeout=300s 2>/dev/null; then
    log_error "Ingress Gateway deployment failed to become available"
    oc get deployment istio-ingressgateway -n bookinfo
    oc get pods -l app=istio-ingressgateway -n bookinfo
    exit 1
fi
log_info "✓ Ingress Gateway deployed"
echo ""

# Step 10: Apply Gateway configuration
log_info "Step 10: Configuring Bookinfo Gateway..."
if ! oc apply -f https://raw.githubusercontent.com/openshift-service-mesh/istio/release-1.24/samples/bookinfo/networking/bookinfo-gateway.yaml -n bookinfo; then
    log_error "Failed to apply gateway configuration"
    exit 1
fi
log_info "✓ Gateway configuration applied"

# Verify gateway
sleep 5
if ! verify_gateway; then
    log_error "Gateway verification failed"
    exit 1
fi
echo ""

# Step 11: Create OpenShift Route
log_info "Step 11: Creating OpenShift Route for external access..."
if oc get route istio-ingressgateway -n bookinfo &> /dev/null; then
    log_warn "Route already exists, skipping creation"
else
    if ! oc expose service istio-ingressgateway -n bookinfo; then
        log_error "Failed to create route"
        exit 1
    fi
    log_info "✓ Route created"
fi

# Verify route
if ! verify_route; then
    log_warn "Route verification had issues, but continuing..."
fi
echo ""

# Final verification
log_info "Running final verification..."
HOST=$(oc get route istio-ingressgateway -n bookinfo -o jsonpath='{.spec.host}')

echo ""
echo "=========================================="
echo "Lab Setup Complete!"
echo "=========================================="
echo ""
echo "Bookinfo Application URL:"
echo "  http://${HOST}/productpage"
echo ""
echo "Verification Commands:"
echo "  Check all components:  ./$(basename $0) verify"
echo "  View pods:             oc get pods -n bookinfo"
echo "  View services:         oc get svc -n bookinfo"
echo "  View gateway:          oc get gateway -n bookinfo"
echo "  View virtual service:  oc get virtualservice -n bookinfo"
echo "  View route:            oc get route -n bookinfo"
echo ""
echo "Testing the Application:"
echo "  curl http://${HOST}/productpage"
echo "  Open in browser: http://${HOST}/productpage"
echo ""
echo "Cleanup:"
echo "  Remove lab: ./$(basename $0) cleanup"
echo ""
echo "=========================================="
