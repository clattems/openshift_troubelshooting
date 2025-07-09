Let’s modify the previous example to use the **troubleshooting-lab** namespace instead of the “dev” namespace, while keeping the rest of the scenario intact. The example still uses a **Service Account (SA)** (`deployer-sa`) to deploy a pod running nginx in OpenShift, incorporating **Role-Based Access Control (RBAC)** and **Security Context Constraints (SCCs)**. The pod requires a specific UID (1000), so we’ll use the `anyuid` SCC. I’ll provide updated YAMLs, commands, and explanations, ensuring everything is tailored for your class and focused on the new namespace.

---

## Scenario
- **Goal**: Deploy a pod running a web server (nginx) in the **troubleshooting-lab** namespace using a service account.
- **Requirements**:
  - A custom service account (`deployer-sa`) needs RBAC permissions to create and manage pods in **troubleshooting-lab**.
  - The pod requires UID 1000, so we’ll assign the `anyuid` SCC to the service account.
- **Steps**:
  1. Create a service account and set up RBAC for pod creation in **troubleshooting-lab**.
  2. Assign the `anyuid` SCC to the service account.
  3. Deploy the pod with the service account and a security context specifying UID 1000.
  4. Verify the deployment and permissions.

---

## Step-by-Step Example

### 1. Create a Service Account and Set Up RBAC
Create a service account (`deployer-sa`) in **troubleshooting-lab** and grant it permissions to create, list, get, and delete pods using a custom Role and RoleBinding.

#### Create the Namespace
- Command:
  ```bash
  oc create namespace troubleshooting-lab
  ```
- **Explanation**: Ensures the **troubleshooting-lab** namespace exists.

#### Create the Service Account
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: deployer-sa
  namespace: troubleshooting-lab
```
- **Save as**: `deployer-sa.yaml`
- **Apply**: `oc create -f deployer-sa.yaml`
- **Explanation**: Creates `deployer-sa` in the **troubleshooting-lab** namespace for pod deployment.

#### Create a Role
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: troubleshooting-lab
  name: pod-manager
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["create", "list", "get", "delete"]
```
- **Save as**: `pod-manager-role.yaml`
- **Apply**: `oc create -f pod-manager-role.yaml`
- **Explanation**: Defines permissions to manage pods in **troubleshooting-lab**.

#### Create a RoleBinding
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: troubleshooting-lab
  name: pod-manager-binding
subjects:
- kind: ServiceAccount
  name: deployer-sa
  namespace: troubleshooting-lab
roleRef:
  kind: Role
  name: pod-manager
  apiGroup: rbac.authorization.k8s.io
```
- **Save as**: `pod-manager-binding.yaml`
- **Apply**: `oc create -f pod-manager-binding.yaml`
- **Explanation**: Binds the `pod-manager` Role to `deployer-sa` in **troubleshooting-lab**, granting pod management permissions.

#### Alternative Command
Instead of YAMLs for RBAC, you can use:
```bash
oc create sa deployer-sa -n troubleshooting-lab
oc adm policy add-role-to-user edit -z deployer-sa -n troubleshooting-lab
```
- **Note**: The `edit` role is broader (includes deployments, services, etc.). We use a custom Role for precision.

#### Verify RBAC
- Check permissions:
  ```bash
  oc auth can-i create pods --as=system:serviceaccount:troubleshooting-lab:deployer-sa -n troubleshooting-lab
  ```
  - Expected output: `yes`
- Test restriction:
  ```bash
  oc auth can-i create deployments --as=system:serviceaccount:troubleshooting-lab:deployer-sa -n troubleshooting-lab
  ```
  - Expected output: `no` (Role only allows pods).

- **Talking Point**: “RBAC ensures our service account can manage pods in troubleshooting-lab, keeping access tightly scoped.”

---

### 2. Assign the `anyuid` SCC
The pod needs to run as UID 1000, requiring the `anyuid` SCC for `deployer-sa`.

#### Assign SCC
- Command:
  ```bash
  oc adm policy add-scc-to-user anyuid -z deployer-sa -n troubleshooting-lab
  ```
- **Explanation**:
  - Links the `anyuid` SCC to `deployer-sa` in **troubleshooting-lab**.
  - Allows pods using this service account to run with any UID (e.g., 1000).
- **Verify**:
  ```bash
  oc describe scc anyuid
  ```
  - Look for `Users` to confirm `system:serviceaccount:troubleshooting-lab:deployer-sa` is listed.

- **Talking Point**: “The `anyuid` SCC lets our pod run with a specific UID, but we only assign it to trusted service accounts.”

---

### 3. Deploy the Pod
Create a pod running nginx with a security context specifying UID 1000 in **troubleshooting-lab**.

#### Pod YAML
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
  namespace: troubleshooting-lab
spec:
  serviceAccountName: deployer-sa
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
    securityContext:
      runAsUser: 1000
```
- **Save as**: `nginx-pod.yaml`
- **Apply** (as an admin or via a CI/CD pipeline with `deployer-sa` credentials):
  ```bash
  oc apply -f nginx-pod.yaml -n troubleshooting-lab
  ```
- **Explanation**:
  - `serviceAccountName: deployer-sa`: Uses `deployer-sa`, which has the `anyuid` SCC and RBAC permissions.
  - `securityContext.runAsUser: 1000`: Forces the container to run as UID 1000.
  - `nginx:latest`: Runs a simple web server.
- **Note**: For demo purposes, you can apply as an admin. In practice, a CI/CD tool would use `deployer-sa`’s token (`oc sa get-token deployer-sa -n troubleshooting-lab`).

- **Talking Point**: “The pod uses our service account to deploy securely, with the SCC enforcing the UID.”

---

### 4. Verify the Deployment
- **Check Pod Status**:
  ```bash
  oc get pods -n troubleshooting-lab
  ```
  - Expected output: `nginx-pod Running`
- **Inspect Pod**:
  ```bash
  oc describe pod nginx-pod -n troubleshooting-lab
  ```
  - Confirm the pod is running and check events for SCC-related issues.
- **Verify UID**:
  - Exec into the pod:
    ```bash
    oc exec -it nginx-pod -n troubleshooting-lab -- id
    ```
    - Expected output: `uid=1000 gid=1000`
- **Test RBAC Restrictions**:
  - Test if `deployer-sa` can create a deployment:
    ```bash
    oc auth can-i create deployments --as=system:serviceaccount:troubleshooting-lab:deployer-sa -n troubleshooting-lab
    ```
    - Expected output: `no` (Role only allows pods).

- **Talking Point**: “Verification confirms RBAC and SCCs work together: the service account deploys the pod, and it runs with UID 1000.”

---

## Troubleshooting (for Class Discussion)
- **Issue**: Pod fails with “Error: permission denied” or “forbidden UID.”
  - **Cause**: `anyuid` SCC not assigned to `deployer-sa`.
  - **Fix**: Re-run `oc adm policy add-scc-to-user anyuid -z deployer-sa -n troubleshooting-lab`.
- **Issue**: Pod creation fails with “forbidden.”
  - **Cause**: RBAC RoleBinding missing or incorrect.
  - **Fix**: Verify with `oc describe rolebinding pod-manager-binding -n troubleshooting-lab` and re-apply the RoleBinding.
- **Command to Debug**:
  ```bash
  oc get events -n troubleshooting-lab
  ```

- **Talking Point**: “In troubleshooting-lab, we simulate real-world issues to learn how to debug RBAC and SCCs.”

---

## For Your Class
- **Simplify for Beginners**: Highlight that the service account automates pod deployment, with RBAC and SCCs ensuring security.
- **Engage Advanced Users**: Discuss service account tokens for CI/CD or auditing SCC assignments in **troubleshooting-lab**.
- **Demo Idea**:
  - Run the steps live with `oc` in **troubleshooting-lab**.
  - Show a failure case (e.g., deploy without `anyuid`, expect a UID error).
- **Visual Aid**:
  - Diagram: RBAC (Service Account → Role → Pod) and SCC (Service Account → anyuid → Pod UID).
  - Command: `oc get pod nginx-pod -n troubleshooting-lab -o yaml | grep -i securityContext` to show UID.
- **Talking Point**: “In troubleshooting-lab, we see how service accounts, RBAC, and SCCs enable secure, automated deployments.”

---

## Additional Notes
- **Prerequisites**:
  - The **troubleshooting-lab** namespace is created as shown.
  - Ensure you have cluster-admin access to apply SCCs and RBAC.
- **Cleanup**:
  ```bash
  oc delete pod nginx-pod -n troubleshooting-lab
  oc delete sa deployer-sa -n troubleshooting-lab
  oc delete role pod-manager -n troubleshooting-lab
  oc delete rolebinding pod-manager-binding -n troubleshooting-lab
  oc adm policy remove-scc-from-user anyuid -z deployer-sa -n troubleshooting-lab
  oc delete namespace troubleshooting-lab
  ```
- **Resources**:
  - OpenShift Docs: [RBAC](https://docs.openshift.com), [SCCs](https://docs.openshift.com).
  - Command: `oc explain pod.spec.securityContext` for security context details.

To enhance your OpenShift class lab in the **troubleshooting-lab** namespace, I’ll extend the existing example by adding a second, more complex **Security Context Constraints (SCC)** example while keeping the current `anyuid` SCC setup. The new SCC will be more intricate, incorporating additional constraints like specific Linux **capabilities**, **SELinux contexts**, and **volume restrictions**, to demonstrate advanced security controls. This will deepen the lab’s exploration of SCCs, complementing the RBAC and service account (`deployer-sa`) setup from your previous example. The goal is to provide a hands-on, complex scenario for your students to understand nuanced SCC configurations while maintaining the existing pod deployment with `anyuid`.

---

## Updated Lab Scenario
- **Current Setup (Recap)**:
  - Namespace: **troubleshooting-lab**
  - Service Account: `deployer-sa` with RBAC permissions to create, list, get, and delete pods.
  - SCC: `anyuid` assigned to `deployer-sa`, allowing a pod (`nginx-pod`) to run with UID 1000.
  - Pod: Nginx web server with `runAsUser: 1000`.
- **New Addition**:
  - Introduce a **custom SCC** (`advanced-scc`) with complex constraints:
    - Specific Linux capabilities (add `NET_ADMIN`, drop `SYS_ADMIN`).
    - Mandatory SELinux context.
    - Restricted volume types (e.g., only `configMap` and `secret`).
    - Read-only root filesystem.
  - Deploy a second pod (`network-tool-pod`) using `advanced-scc` to run a network diagnostic tool (e.g., `busybox` with `ip` commands).
  - Use the same `deployer-sa`, updating RBAC to allow managing both pods.
- **Objectives**:
  - Compare the simple `anyuid` SCC with the complex `advanced-scc`.
  - Demonstrate troubleshooting SCC misconfigurations.
  - Reinforce RBAC and service account usage.

---

## Step-by-Step Enhanced Lab

### 1. Verify Existing Setup
Ensure the current setup (from your previous example) is in place for the `anyuid` SCC and `nginx-pod`.

#### Confirm Namespace and Service Account
- **Namespace**:
  ```bash
  oc create namespace troubleshooting-lab
  ```
- **Service Account**:
  ```yaml
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: deployer-sa
    namespace: troubleshooting-lab
  ```
  - Apply: `oc create -f deployer-sa.yaml`

#### Confirm RBAC
- **Role**:
  ```yaml
  apiVersion: rbac.authorization.k8s.io/v1
  kind: Role
  metadata:
    namespace: troubleshooting-lab
    name: pod-manager
  rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["create", "list", "get", "delete"]
  ```
  - Apply: `oc create -f pod-manager-role.yaml`
- **RoleBinding**:
  ```yaml
  apiVersion: rbac.authorization.k8s.io/v1
  kind: RoleBinding
  metadata:
    namespace: troubleshooting-lab
    name: pod-manager-binding
  subjects:
  - kind: ServiceAccount
    name: deployer-sa
    namespace: troubleshooting-lab
  roleRef:
    kind: Role
    name: pod-manager
    apiGroup: rbac.authorization.k8s.io
  ```
  - Apply: `oc create -f pod-manager-binding.yaml`
- **Verify Permissions**:
  ```bash
  oc auth can-i create pods --as=system:serviceaccount:troubleshooting-lab:deployer-sa -n troubleshooting-lab
  ```
  - Expected: `yes`

#### Confirm `anyuid` SCC
- Assign:
  ```bash
  oc adm policy add-scc-to-user anyuid -z deployer-sa -n troubleshooting-lab
  ```
- Verify:
  ```bash
  oc describe scc anyuid | grep deployer-sa
  ```
  - Should show `system:serviceaccount:troubleshooting-lab:deployer-sa`.

#### Deploy Existing Pod (`nginx-pod`)
- **Pod YAML**:
  ```yaml
  apiVersion: v1
  kind: Pod
  metadata:
    name: nginx-pod
    namespace: troubleshooting-lab
  spec:
    serviceAccountName: deployer-sa
    containers:
    - name: nginx
      image: nginx:latest
      ports:
      - containerPort: 80
      securityContext:
        runAsUser: 1000
  ```
  - Apply:
    ```bash
    TOKEN=$(oc sa get-token deployer-sa -n troubleshooting-lab)
    oc --token="$TOKEN" --server=$(oc whoami --show-server) apply -f nginx-pod.yaml -n troubleshooting-lab
    ```
  - Verify:
    ```bash
    oc get pods -n troubleshooting-lab
    oc exec -it nginx-pod -n troubleshooting-lab -- id
    ```
    - Expected: `uid=1000 gid=1000`

- **Talking Point**: “Our existing setup uses `anyuid` for simple UID flexibility. Now, let’s add a complex SCC to see advanced controls.”

---

### 2. Create a Complex SCC (`advanced-scc`)
Define a new SCC with intricate constraints to demonstrate advanced security features.

#### Custom SCC YAML
```yaml
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: advanced-scc
allowPrivilegedContainer: false
allowHostDirVolumePlugin: false
allowedCapabilities:
- NET_ADMIN
requiredDropCapabilities:
- SYS_ADMIN
- KILL
runAsUser:
  type: MustRunAsRange
  uidRangeMin: 2000
  uidRangeMax: 2999
seLinuxContext:
  type: MustRunAs
  seLinuxOptions:
    level: "s0:c123,c456"
fsGroup:
  type: MustRunAs
supplementalGroups:
  type: MustRunAs
readOnlyRootFilesystem: true
volumes:
- configMap
- secret
```
- **Save as**: `advanced-scc.yaml`
- **Apply**: `oc create -f advanced-scc.yaml`

#### Explanation of Constraints
- **Capabilities**:
  - `allowedCapabilities: [NET_ADMIN]`: Allows the pod to manage network settings (e.g., for network diagnostics).
  - `requiredDropCapabilities: [SYS_ADMIN, KILL]`: Drops dangerous capabilities to prevent system admin tasks or process termination.
- **runAsUser**:
  - `MustRunAsRange`, `uidRangeMin: 2000`, `uidRangeMax: 2999`: Pod must run with a UID between 2000–2999 (e.g., 2000 for our example).
- **seLinuxContext**:
  - `MustRunAs`, `level: "s0:c123,c456"`: Enforces a specific SELinux context for enhanced security (requires SELinux enabled on the cluster).
- **fsGroup** and **supplementalGroups**:
  - `MustRunAs`: Ensures volumes and supplemental groups align with the pod’s security context.
- **readOnlyRootFilesystem: true**:
  - Forces the container’s root filesystem to be read-only, preventing writes for added security.
- **volumes**:
  - Restricts volumes to `configMap` and `secret`, blocking hostPath or persistentVolumeClaim for safety.
- **Talking Point**: “This SCC is strict: it limits capabilities, enforces SELinux, restricts UIDs, and blocks writable filesystems or risky volumes.”

---

### 3. Assign `advanced-scc` to `deployer-sa`
Allow `deployer-sa` to use the new `advanced-scc` in **troubleshooting-lab**.

- **Command**:
  ```bash
  oc adm policy add-scc-to-user advanced-scc -z deployer-sa -n troubleshooting-lab
  ```
- **Verify**:
  ```bash
  oc describe scc advanced-scc | grep deployer-sa
  ```
  - Should show `system:serviceaccount:troubleshooting-lab:deployer-sa`.

- **Talking Point**: “Now `deployer-sa` can use both `anyuid` for the nginx pod and `advanced-scc` for a new, more restricted pod.”

---

### 4. Deploy a New Pod with `advanced-scc`
Create a pod (`network-tool-pod`) running a network diagnostic tool (busybox) that requires `NET_ADMIN` and complies with `advanced-scc` constraints.

#### Pod YAML
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: network-tool-pod
  namespace: troubleshooting-lab
spec:
  serviceAccountName: deployer-sa
  containers:
  - name: network-tool
    image: busybox:latest
    command: ["sh", "-c", "ip addr && sleep 3600"]
    securityContext:
      runAsUser: 2000
      capabilities:
        add: ["NET_ADMIN"]
      seLinuxOptions:
        level: "s0:c123,c456"
      readOnlyRootFilesystem: true
    volumeMounts:
    - name: config-data
      mountPath: "/config"
      readOnly: true
  volumes:
  - name: config-data
    configMap:
      name: network-tool-config
```
- **Save as**: `network-tool-pod.yaml`

#### Create a ConfigMap (for the Volume)
- **ConfigMap YAML**:
  ```yaml
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: network-tool-config
    namespace: troubleshooting-lab
  data:
    config.txt: |
      Sample configuration for network tool
  ```
  - Apply: `oc create -f network-tool-config.yaml`

#### Deploy the Pod
- **Command**:
  ```bash
  TOKEN=$(oc sa get-token deployer-sa -n troubleshooting-lab)
  oc --token="$TOKEN" --server=$(oc whoami --show-server) apply -f network-tool-pod.yaml -n troubleshooting-lab
  ```
- **Explanation**:
  - `serviceAccountName: deployer-sa`: Uses `deployer-sa`, which has `advanced-scc`.
  - `runAsUser: 2000`: Complies with `advanced-scc`’s UID range (2000–2999).
  - `capabilities.add: ["NET_ADMIN"]`: Requests `NET_ADMIN`, allowed by `advanced-scc`.
  - `seLinuxOptions`: Matches `advanced-scc`’s required SELinux level.
  - `readOnlyRootFilesystem: true`: Enforces read-only filesystem.
  - `volumes` and `volumeMounts`: Uses a `configMap` volume, allowed by `advanced-scc`.
  - `command`: Runs `ip addr` to test `NET_ADMIN` and sleeps to keep the pod running.

#### Verify Pod
- **Check Status**:
  ```bash
  oc get pods -n troubleshooting-lab
  ```
  - Expected: `network-tool-pod Running`
- **Verify UID**:
  ```bash
  oc exec -it network-tool-pod -n troubleshooting-lab -- id
  ```
  - Expected: `uid=2000`
- **Test Network Command**:
  ```bash
  oc exec -it network-tool-pod -n troubleshooting-lab -- ip addr
  ```
  - Should display network interfaces, confirming `NET_ADMIN`.
- **Test Read-Only Filesystem**:
  ```bash
  oc exec -it network-tool-pod -n troubleshooting-lab -- touch /test.txt
  ```
  - Expected: `touch: /test.txt: Read-only file system`

- **Talking Point**: “This pod uses `advanced-scc`’s strict rules, showing how capabilities, SELinux, and volume restrictions work together.”

---

### 5. Simulate a Misconfiguration (Troubleshooting Exercise)
To deepen the lab, have students troubleshoot a deliberately incorrect pod configuration to learn SCC debugging.

#### Incorrect Pod YAML
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: network-tool-pod-fail
  namespace: troubleshooting-lab
spec:
  serviceAccountName: deployer-sa
  containers:
  - name: network-tool
    image: busybox:latest
    command: ["sh", "-c", "ip addr && sleep 3600"]
    securityContext:
      runAsUser: 1000  # Wrong UID (outside 2000–2999)
      capabilities:
        add: ["SYS_ADMIN"]  # Disallowed capability
      seLinuxOptions:
        level: "s0:c999,c999"  # Wrong SELinux level
      readOnlyRootFilesystem: false  # Violates read-only requirement
    volumeMounts:
    - name: host-path
      mountPath: "/host"
  volumes:
  - name: host-path
    hostPath:
      path: /var/log  # Disallowed volume type
```
- **Save as**: `network-tool-pod-fail.yaml`
- **Apply** (as `deployer-sa`):
  ```bash
  oc --token="$TOKEN" --server=$(oc whoami --show-server) apply -f network-tool-pod-fail.yaml -n troubleshooting-lab
  ```
- **Expected Failure**:
  - Pod will fail to start. Check events:
    ```bash
    oc get events -n troubleshooting-lab
    ```
  - Likely errors:
    - “UID 1000 is not in range 2000–2999.”
    - “Capability SYS_ADMIN is not allowed.”
    - “SELinux level s0:c999,c999 does not match s0:c123,c456.”
    - “hostPath volumes are not allowed.”
    - “readOnlyRootFilesystem must be true.”

#### Troubleshooting Steps (for Students)
- **Check Pod Status**:
  ```bash
  oc describe pod network-tool-pod-fail -n troubleshooting-lab
  ```
- **Compare with SCC**:
  ```bash
  oc describe scc advanced-scc
  ```
- **Fix the YAML**:
  - Update `runAsUser: 2000`.
  - Change `capabilities.add: ["NET_ADMIN"]`.
  - Set `seLinuxOptions.level: "s0:c123,c456"`.
  - Set `readOnlyRootFilesystem: true`.
  - Replace `hostPath` with a `configMap` volume.
- **Re-apply** and verify.

- **Talking Point**: “This exercise shows why SCCs are powerful but tricky. Misconfigurations lead to clear errors we can debug.”

---

### 6. Compare SCCs in the Lab
Guide students to compare the two SCCs and their pods:
- **anyuid SCC** (nginx-pod):
  - Simple: Allows any UID (e.g., 1000).
  - Minimal restrictions (no capability or volume limits).
  - Use case: Legacy apps needing specific UIDs.
- **advanced-scc** (network-tool-pod):
  - Complex: Restricts UIDs, capabilities, SELinux, volumes, and filesystem.
  - Use case: Security-sensitive apps (e.g., network tools) requiring specific permissions.
- **Command to Compare**:
  ```bash
  oc describe scc anyuid > anyuid.txt
  oc describe scc advanced-scc > advanced-scc.txt
  diff anyuid.txt advanced-scc.txt
  ```

- **Talking Point**: “Comparing `anyuid` and `advanced-scc` shows how SCCs scale from simple to highly restrictive.”

---

## For Your Class
- **Simplify for Beginners**:
  - Focus on `anyuid` for ease and `advanced-scc`’s read-only filesystem and volume restrictions.
  - Explain capabilities (`NET_ADMIN` for network commands) simply.
- **Engage Advanced Users**:
  - Discuss SELinux integration and why `MustRunAs` is critical in multi-tenant clusters.
  - Explore auditing: `oc get scc advanced-scc -o yaml | grep -i capabilities`.
- **Demo Idea**:
  - Deploy both pods live (`nginx-pod` and `network-tool-pod`).
  - Show the failed pod deployment and walk through fixing one issue (e.g., UID).
  - Script:
    ```bash
    # Deploy nginx-pod (anyuid)
    TOKEN=$(oc sa get-token deployer-sa -n troubleshooting-lab)
    oc --token="$TOKEN" --server=$(oc whoami --show-server) apply -f nginx-pod.yaml -n troubleshooting-lab
    oc get pods -n troubleshooting-lab
    # Create advanced-scc
    oc create -f advanced-scc.yaml
    oc adm policy add-scc-to-user advanced-scc -z deployer-sa -n troubleshooting-lab
    # Deploy network-tool-pod (advanced-scc)
    oc create -f network-tool-config.yaml
    oc --token="$TOKEN" --server=$(oc whoami --show-server) apply -f network-tool-pod.yaml -n troubleshooting-lab
    oc exec -it network-tool-pod -n troubleshooting-lab -- ip addr
    # Show failure case
    oc --token="$TOKEN" --server=$(oc whoami --show-server) apply -f network-tool-pod-fail.yaml -n troubleshooting-lab
    oc describe pod network-tool-pod-fail -n troubleshooting-lab
    ```
- **Visual Aid**:
  - Diagram: `deployer-sa` → RBAC → Two Pods (`nginx-pod` → `anyuid`, `network-tool-pod` → `advanced-scc`).
  - Table comparing SCCs:
    | Feature                 | anyuid SCC         | advanced-scc                     |
    |-------------------------|--------------------|----------------------------------|
    | UID                     | Any                | 2000–2999                        |
    | Capabilities            | None restricted    | Add `NET_ADMIN`, drop `SYS_ADMIN`|
    | SELinux                 | Optional           | Mandatory (`s0:c123,c456`)       |
    | Filesystem              | Writable           | Read-only                        |
    | Volumes                 | Any                | Only `configMap`, `secret`       |
- **Talking Point**: “In troubleshooting-lab, we use two SCCs to contrast simple and complex security, preparing you for real-world scenarios.”

---

## Troubleshooting Tips (for Students)
- **SCC Mismatch**:
  - Symptom: Pod fails with “forbidden” or “invalid” errors.
  - Fix: Check SCC assignment (`oc describe scc advanced-scc`) and pod spec (`oc get pod network-tool-pod -o yaml`).
- **SELinux Issues**:
  - Symptom: “SELinux context mismatch.”
  - Fix: Ensure pod’s `seLinuxOptions` matches `advanced-scc` (`s0:c123,c456`).
- **Capability Errors**:
  - Symptom: “NET_ADMIN not allowed” or “SYS_ADMIN required.”
  - Fix: Verify `allowedCapabilities` and `requiredDropCapabilities` in `advanced-scc`.
- **Command**:
  ```bash
  oc get events -n troubleshooting-lab
  ```

---

## Additional Notes
- **Prerequisites**:
  - Ensure **troubleshooting-lab** exists and `deployer-sa` is set up.
  - SELinux must be enabled on the cluster for `seLinuxContext` to work (common in OpenShift).
- **Cleanup**:
  ```bash
  oc delete pod nginx-pod network-tool-pod network-tool-pod-fail -n troubleshooting-lab
  oc delete configmap network-tool-config -n troubleshooting-lab
  oc delete sa deployer-sa -n troubleshooting-lab
  oc delete role pod-manager -n troubleshooting-lab
  oc delete rolebinding pod-manager-binding -n troubleshooting-lab
  oc adm policy remove-scc-from-user anyuid -z deployer-sa -n troubleshooting-lab
  oc adm policy remove-scc-from-user advanced-scc -z deployer-sa -n troubleshooting-lab
  oc delete scc advanced-scc
  oc delete namespace troubleshooting-lab
  ```
- **Resources**:
  - OpenShift Docs: [SCCs](https://docs.openshift.com), [RBAC](https://docs.openshift.com).
  - Linux: `man capabilities`, `man selinux`.

If you need a full demo script, additional failure cases, or slides for this enhanced lab in **troubleshooting-lab**, let me know!
