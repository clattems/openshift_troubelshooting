# OpenShift Troubleshooting Lab Scripts

This collection of scripts creates common OpenShift issues for hands-on troubleshooting practice.

## Prerequisites

Run these commands before starting the lab exercises:

```bash
# Create a dedicated namespace for troubleshooting exercises
oc new-project troubleshooting-lab

# Switch to the lab namespace
oc project troubleshooting-lab
```

## 1. CrashLooping Pod

Creates a pod that continuously crashes and restarts.

```bash
# crashloop-pod.yaml
cat << 'EOF' > crashloop-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: crashloop-app
  labels:
    app: crashloop-demo
spec:
  containers:
  - name: crashloop-container
    image: busybox:latest
    command: ["/bin/sh"]
    args: ["-c", "echo 'Starting application...'; sleep 5; echo 'Simulating crash!'; exit 1"]
  restartPolicy: Always
EOF

# Deploy the crashlooping pod
oc apply -f crashloop-pod.yaml

echo "CrashLooping pod deployed. Check status with: oc get pods -w"
```

## 2. Memory Limit Exceeded (OOMKilled)

Creates a pod that exceeds memory limits and gets killed.

```bash
# oom-pod.yaml
cat << 'EOF' > oom-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: memory-hog
  labels:
    app: oom-demo
spec:
  containers:
  - name: memory-consumer
    image: busybox:latest
    command: ["/bin/sh"]
    args: ["-c", "echo 'Consuming memory...'; dd if=/dev/zero of=/tmp/memory.fill bs=1M count=200; sleep 3600"]
    resources:
      limits:
        memory: "128Mi"
      requests:
        memory: "64Mi"
EOF

# Deploy the OOM pod
oc apply -f oom-pod.yaml

echo "OOM pod deployed. It will be killed due to memory limits."
echo "Monitor with: oc get pods -w"
```

## 3. Image Pull Error

Creates a pod that fails to pull a non-existent image.

```bash
# imagepull-error.yaml
cat << 'EOF' > imagepull-error.yaml
apiVersion: v1
kind: Pod
metadata:
  name: broken-image
  labels:
    app: imagepull-demo
spec:
  containers:
  - name: broken-container
    image: nonexistent/fake-image:v1.0.0
    command: ["echo", "This will never run"]
EOF

# Deploy the broken image pod
oc apply -f imagepull-error.yaml

echo "ImagePullError pod deployed. Check with: oc describe pod broken-image"
```

## 4. Unhealthy Application with Failing Health Checks

Creates a deployment with health checks that fail.

```bash
# unhealthy-app.yaml
cat << 'EOF' > unhealthy-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: unhealthy-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: unhealthy-demo
  template:
    metadata:
      labels:
        app: unhealthy-demo
    spec:
      containers:
      - name: web-server
        image: nginx:alpine
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 5
        readinessProbe:
          httpGet:
            path: /ready
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 3
EOF

# Deploy the unhealthy app
oc apply -f unhealthy-app.yaml

echo "Unhealthy app deployed. Health checks will fail because /health and /ready endpoints don't exist."
echo "Check with: oc get pods and oc describe deployment unhealthy-app"
```

## 5. Resource Quota Exceeded

Creates resource quotas and then tries to exceed them.

```bash
# Create resource quota
cat << 'EOF' > resource-quota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
spec:
  hard:
    requests.cpu: "1"
    requests.memory: 1Gi
    limits.cpu: "2"
    limits.memory: 2Gi
    pods: "2"
EOF

oc apply -f resource-quota.yaml

# Try to create a deployment that exceeds the quota
cat << 'EOF' > quota-breaker.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: quota-breaker
spec:
  replicas: 5
  selector:
    matchLabels:
      app: quota-demo
  template:
    metadata:
      labels:
        app: quota-demo
    spec:
      containers:
      - name: resource-hog
        image: busybox:latest
        command: ["sleep", "3600"]
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "1"
            memory: "1Gi"
EOF

oc apply -f quota-breaker.yaml

echo "Resource quota created and quota-breaking deployment attempted."
echo "Check quota status with: oc describe quota compute-quota"
echo "Check deployment status with: oc describe deployment quota-breaker"
```

## 6. Persistent Volume Mount Issues

Creates a pod that fails due to PVC mounting problems.

```bash
# Create a PVC that references a non-existent storage class
cat << 'EOF' > broken-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: broken-storage
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: non-existent-storage-class
EOF

oc apply -f broken-pvc.yaml

# Create a pod that tries to use the broken PVC
cat << 'EOF' > pvc-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: storage-app
spec:
  containers:
  - name: app
    image: busybox:latest
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: broken-storage
EOF

oc apply -f pvc-pod.yaml

echo "PVC and pod with storage issues created."
echo "Check PVC status with: oc get pvc"
echo "Check pod status with: oc describe pod storage-app"
```

## 7. Network Policy Blocking Traffic

Creates a deployment and service, then blocks traffic with network policies.

```bash
# Create a simple web app
cat << 'EOF' > web-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web-demo
  template:
    metadata:
      labels:
        app: web-demo
    spec:
      containers:
      - name: web
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web-service
spec:
  selector:
    app: web-demo
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF

oc apply -f web-app.yaml

# Create a restrictive network policy
cat << 'EOF' > deny-all-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-traffic
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

oc apply -f deny-all-policy.yaml

echo "Web app and restrictive network policy created."
echo "Test connectivity with: oc run test-pod --image=busybox:latest --rm -it -- wget -qO- web-service"
```

## 8. Node Resource Pressure

Creates multiple resource-intensive pods to simulate node pressure.

```bash
# Create multiple CPU-intensive pods
for i in {1..3}; do
cat << EOF > cpu-stress-$i.yaml
apiVersion: v1
kind: Pod
metadata:
  name: cpu-stress-$i
spec:
  containers:
  - name: cpu-burner
    image: busybox:latest
    command: ["/bin/sh"]
    args: ["-c", "while true; do echo 'Burning CPU...'; done"]
    resources:
      requests:
        cpu: "100m"
      limits:
        cpu: "500m"
EOF
oc apply -f cpu-stress-$i.yaml
done

echo "Multiple CPU-intensive pods created to simulate node pressure."
echo "Monitor node status with: oc describe nodes"
echo "Check pod scheduling with: oc get pods -o wide"
```

## 9. ConfigMap/Secret Mount Issues

Creates pods with missing or incorrectly mounted config.

```bash
# Create a pod that references a non-existent ConfigMap
cat << 'EOF' > missing-config.yaml
apiVersion: v1
kind: Pod
metadata:
  name: missing-config-app
spec:
  containers:
  - name: app
    image: busybox:latest
    command: ["sleep", "3600"]
    env:
    - name: CONFIG_VALUE
      valueFrom:
        configMapKeyRef:
          name: missing-configmap
          key: config-key
EOF

oc apply -f missing-config.yaml

# Create a pod that references a non-existent Secret
cat << 'EOF' > missing-secret.yaml
apiVersion: v1
kind: Pod
metadata:
  name: missing-secret-app
spec:
  containers:
  - name: app
    image: busybox:latest
    command: ["sleep", "3600"]
    volumeMounts:
    - name: secret-volume
      mountPath: /etc/secrets
  volumes:
  - name: secret-volume
    secret:
      secretName: missing-secret
EOF

oc apply -f missing-secret.yaml

echo "Pods with missing ConfigMap and Secret references created."
echo "Check with: oc describe pod missing-config-app"
echo "Check with: oc describe pod missing-secret-app"
```

## Cleanup Script

Run this to clean up all the troubleshooting resources:

```bash
#!/bin/bash
# cleanup-lab.sh

echo "Cleaning up troubleshooting lab resources..."

# Delete all pods
oc delete pod --all

# Delete deployments
oc delete deployment --all

# Delete services
oc delete service --all

# Delete PVCs
oc delete pvc --all

# Delete network policies
oc delete networkpolicy --all

# Delete resource quotas
oc delete quota --all

# Delete YAML files
rm -f *.yaml

echo "Cleanup complete!"
```

## Troubleshooting Commands Reference

Here are the key commands students should use to diagnose these issues:

```bash
# Pod status and events
oc get pods
oc get pods -w
oc describe pod <pod-name>

# Logs
oc logs <pod-name>
oc logs <pod-name> -p  # Previous container logs

# Resource usage
oc top pods
oc top nodes

# Events
oc get events --sort-by='.lastTimestamp'

# Deployment status
oc get deployments
oc describe deployment <deployment-name>

# Resource quotas
oc get quota
oc describe quota <quota-name>

# Storage
oc get pv
oc get pvc
oc describe pvc <pvc-name>

# Network
oc get networkpolicies
oc describe networkpolicy <policy-name>

# Node status
oc get nodes
oc describe node <node-name>
```

## Expected Issues Summary

1. **CrashLooping Pod**: Pod restarts continuously due to exit code 1
2. **OOM Killed**: Pod terminated due to memory limit exceeded
3. **ImagePullError**: Cannot pull non-existent container image
4. **Health Check Failures**: Readiness/liveness probes fail
5. **Resource Quota Exceeded**: Cannot create resources due to quota limits
6. **PVC Mount Issues**: Storage class doesn't exist, PVC pending
7. **Network Policy Blocking**: Traffic blocked by restrictive policies
8. **Node Pressure**: Resource contention on nodes
9. **Missing Config/Secrets**: Pods fail due to missing configuration

Each scenario provides realistic troubleshooting practice with different OpenShift CLI commands and debugging techniques.
