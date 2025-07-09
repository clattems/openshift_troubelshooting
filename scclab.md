1. Create a Service Account and Set Up RBACCreate a service account (deployer-sa) in troubleshooting-lab and grant it permissions to create, list, get, and delete pods using a custom Role and RoleBinding.Create the NamespaceCommand:bash

oc create namespace troubleshooting-lab

Explanation: Ensures the troubleshooting-lab namespace exists.

Create the Service Accountyaml

apiVersion: v1
kind: ServiceAccount
metadata:
  name: deployer-sa
  namespace: troubleshooting-lab

Save as: deployer-sa.yaml
Apply: oc create -f deployer-sa.yaml
Explanation: Creates deployer-sa in the troubleshooting-lab namespace for pod deployment.

Create a Roleyaml

apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: troubleshooting-lab
  name: pod-manager
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["create", "list", "get", "delete"]

Save as: pod-manager-role.yaml
Apply: oc create -f pod-manager-role.yaml
Explanation: Defines permissions to manage pods in troubleshooting-lab.

Create a RoleBindingyaml

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

Save as: pod-manager-binding.yaml
Apply: oc create -f pod-manager-binding.yaml
Explanation: Binds the pod-manager Role to deployer-sa in troubleshooting-lab, granting pod management permissions.

Alternative CommandInstead of YAMLs for RBAC, you can use:bash

oc create sa deployer-sa -n troubleshooting-lab
oc adm policy add-role-to-user edit -z deployer-sa -n troubleshooting-lab

Note: The edit role is broader (includes deployments, services, etc.). We use a custom Role for precision.

Verify RBACCheck permissions:bash

oc auth can-i create pods --as=system:serviceaccount:troubleshooting-lab:deployer-sa -n troubleshooting-lab

Expected output: yes

Test restriction:bash

oc auth can-i create deployments --as=system:serviceaccount:troubleshooting-lab:deployer-sa -n troubleshooting-lab

Expected output: no (Role only allows pods).

Talking Point: “RBAC ensures our service account can manage pods in troubleshooting-lab, keeping access tightly scoped.”

2. Assign the anyuid SCCThe pod needs to run as UID 1000, requiring the anyuid SCC for deployer-sa.Assign SCCCommand:bash

oc adm policy add-scc-to-user anyuid -z deployer-sa -n troubleshooting-lab

Explanation:Links the anyuid SCC to deployer-sa in troubleshooting-lab.
Allows pods using this service account to run with any UID (e.g., 1000).

Verify:bash

oc describe scc anyuid

Look for Users to confirm system:serviceaccount:troubleshooting-lab:deployer-sa is listed.

Talking Point: “The anyuid SCC lets our pod run with a specific UID, but we only assign it to trusted service accounts.”

3. Deploy the PodCreate a pod running nginx with a security context specifying UID 1000 in troubleshooting-lab.Pod YAMLyaml

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

Save as: nginx-pod.yaml
Apply (as an admin or via a CI/CD pipeline with deployer-sa credentials):bash

oc apply -f nginx-pod.yaml -n troubleshooting-lab

Explanation:serviceAccountName: deployer-sa: Uses deployer-sa, which has the anyuid SCC and RBAC permissions.
securityContext.runAsUser: 1000: Forces the container to run as UID 1000.
nginx:latest: Runs a simple web server.

Note: For demo purposes, you can apply as an admin. In practice, a CI/CD tool would use deployer-sa’s token (oc sa get-token deployer-sa -n troubleshooting-lab).
Talking Point: “The pod uses our service account to deploy securely, with the SCC enforcing the UID.”

4. Verify the DeploymentCheck Pod Status:bash

oc get pods -n troubleshooting-lab

Expected output: nginx-pod Running

Inspect Pod:bash

oc describe pod nginx-pod -n troubleshooting-lab

Confirm the pod is running and check events for SCC-related issues.

Verify UID:Exec into the pod:bash

oc exec -it nginx-pod -n troubleshooting-lab -- id

Expected output: uid=1000 gid=1000

Test RBAC Restrictions:Test if deployer-sa can create a deployment:bash

oc auth can-i create deployments --as=system:serviceaccount:troubleshooting-lab:deployer-sa -n troubleshooting-lab

Expected output: no (Role only allows pods).

Talking Point: “Verification confirms RBAC and SCCs work together: the service account deploys the pod, and it runs with UID 1000.”

Troubleshooting (for Class Discussion)Issue: Pod fails with “Error: permission denied” or “forbidden UID.”Cause: anyuid SCC not assigned to deployer-sa.
Fix: Re-run oc adm policy add-scc-to-user anyuid -z deployer-sa -n troubleshooting-lab.

Issue: Pod creation fails with “forbidden.”Cause: RBAC RoleBinding missing or incorrect.
Fix: Verify with oc describe rolebinding pod-manager-binding -n troubleshooting-lab and re-apply the RoleBinding.

Command to Debug:bash

oc get events -n troubleshooting-lab

Talking Point: “In troubleshooting-lab, we simulate real-world issues to learn how to debug RBAC and SCCs.”

For Your ClassSimplify for Beginners: Highlight that the service account automates pod deployment, with RBAC and SCCs ensuring security.
Engage Advanced Users: Discuss service account tokens for CI/CD or auditing SCC assignments in troubleshooting-lab.
Demo Idea:Run the steps live with oc in troubleshooting-lab.
Show a failure case (e.g., deploy without anyuid, expect a UID error).

Visual Aid:Diagram: RBAC (Service Account → Role → Pod) and SCC (Service Account → anyuid → Pod UID).
Command: oc get pod nginx-pod -n troubleshooting-lab -o yaml | grep -i securityContext to show UID.

Talking Point: “In troubleshooting-lab, we see how service accounts, RBAC, and SCCs enable secure, automated deployments.”

Additional NotesPrerequisites:The troubleshooting-lab namespace is created as shown.
Ensure you have cluster-admin access to apply SCCs and RBAC.

Cleanup:bash

oc delete pod nginx-pod -n troubleshooting-lab
oc delete sa deployer-sa -n troubleshooting-lab
oc delete role pod-manager -n troubleshooting-lab
oc delete rolebinding pod-manager-binding -n troubleshooting-lab
oc adm policy remove-scc-from-user anyuid -z deployer-sa -n troubleshooting-lab
oc delete namespace troubleshooting-lab

Resources:OpenShift Docs: RBAC, SCCs.
Command: oc explain pod.spec.securityContext for security context details.

