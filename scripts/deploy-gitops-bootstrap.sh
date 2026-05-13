#!/bin/bash
set -euo pipefail

# ══════════════════════════════════════════════════════════════════════════════
# EKS GitOps Bootstrap Script
# ══════════════════════════════════════════════════════════════════════════════
# This script automates the manual pre-GitOps steps for baseline node setup.
# Run this AFTER Terraform apply completes and cluster is ready.
# ══════════════════════════════════════════════════════════════════════════════

CLUSTER_NAME="eks-production"
AWS_REGION="ap-southeast-1"
GITOPS_REPO_PATH="./eks-gitops-patterns"
TERRAFORM_PATH="./eks-terraform-infrastructure"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v aws >/dev/null 2>&1 || missing_tools+=("aws")
    command -v terraform >/dev/null 2>&1 || missing_tools+=("terraform")
    command -v git >/dev/null 2>&1 || missing_tools+=("git")

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    # Check kubeconfig
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster. Run: aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION"
        exit 1
    fi

    log_success "All prerequisites met"
}

install_argocd() {
    log_info "Installing ArgoCD..."

    # Create namespace if it doesn't exist
    if ! kubectl get namespace argocd >/dev/null 2>&1; then
        kubectl create namespace argocd
    fi

    # Check if ArgoCD is already installed
    if kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
        log_warning "ArgoCD already installed, updating..."
    fi

    # Use server-side apply to avoid annotation size limits
    # Force conflicts to overwrite any previous client-side applies
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side --force-conflicts

    log_info "Waiting for ArgoCD to be ready (may take 2-3 minutes)..."
    sleep 10 # Give it a moment to start creating pods
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s || true

    log_success "ArgoCD installed"
}

update_argocd_placement() {
    log_info "Checking ArgoCD placement for baseline nodes..."

    # Since baseline nodes have NO taints, we don't need the placement patch
    # ArgoCD can run on any node

    if [ -f "$GITOPS_REPO_PATH/bootstrap/argocd-placement-patch.yaml" ]; then
        log_warning "Found argocd-placement-patch.yaml - This file is for tainted nodes"
        log_warning "Baseline nodes have NO taints, so this patch is NOT needed"
        log_info "Skipping ArgoCD placement patch"
    fi

    log_success "ArgoCD placement OK (baseline nodes accept all workloads)"
}

setup_git_repository_access() {
    log_info "Setting up Git repository access..."

    # Check if secret already exists
    if kubectl get secret private-repo-eks-gitops -n argocd >/dev/null 2>&1; then
        log_warning "Repository secret already exists, skipping"
        return 0
    fi

    # Check for SSH key
    if [ ! -f ~/.ssh/argocd-deploy-key ]; then
        log_error "SSH deploy key not found at ~/.ssh/argocd-deploy-key"
        log_info "Generate one with: ssh-keygen -t ed25519 -C 'argocd@eks-cluster' -f ~/.ssh/argocd-deploy-key -N ''"
        log_info "Then add the public key to GitHub: https://github.com/gryffin-uit-alpha/eks-gitops-patterns/settings/keys"
        read -p "Press Enter after adding the deploy key to GitHub..."
    fi

    # Create repository secret
    kubectl create secret generic private-repo-eks-gitops \
      -n argocd \
      --from-literal=type=git \
      --from-literal=url=git@github.com:gryffin-uit-alpha/eks-gitops-patterns.git \
      --from-file=sshPrivateKey=$HOME/.ssh/argocd-deploy-key

    # Label the secret
    kubectl label secret private-repo-eks-gitops \
      -n argocd \
      argocd.argoproj.io/secret-type=repository

    log_success "Git repository access configured"
}

install_sealed_secrets() {
    log_info "Installing Sealed Secrets controller..."

    if kubectl get deployment sealed-secrets-controller -n kube-system >/dev/null 2>&1; then
        log_warning "Sealed Secrets already installed, skipping"
        return 0
    fi

    kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/controller.yaml

    log_info "Waiting for Sealed Secrets controller to be ready..."
    kubectl wait --for=condition=Ready pod -l name=sealed-secrets-controller -n kube-system --timeout=180s || true

    # Wait a bit for the controller to generate the key
    log_info "Waiting for master key to be generated..."
    sleep 10

    # Backup the sealing key (find by label as the name has a suffix)
    log_warning "IMPORTANT: Backing up Sealed Secrets master key..."
    MASTER_KEY_NAME=$(kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o jsonpath='{.items[0].metadata.name}')
    kubectl get secret -n kube-system "$MASTER_KEY_NAME" -o yaml > sealed-secrets-master-key.yaml
    log_warning "Master key saved to: sealed-secrets-master-key.yaml"
    log_warning "Store this file SECURELY! You cannot decrypt secrets without it!"

    log_success "Sealed Secrets controller installed"
}

install_ebs_csi_driver() {
    log_info "Installing EBS CSI Driver..."

    # Check if addon already exists
    if aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name aws-ebs-csi-driver --region "$AWS_REGION" >/dev/null 2>&1; then
        log_warning "EBS CSI Driver already installed, skipping"
        return 0
    fi

    # Get IAM role ARN from Terraform
    cd "$TERRAFORM_PATH"
    EBS_CSI_ROLE_ARN=$(terraform output -raw ebs_csi_driver_role_arn)
    cd - >/dev/null

    log_info "Creating EBS CSI Driver addon with role: $EBS_CSI_ROLE_ARN"

    aws eks create-addon \
      --cluster-name "$CLUSTER_NAME" \
      --addon-name aws-ebs-csi-driver \
      --service-account-role-arn "$EBS_CSI_ROLE_ARN" \
      --region "$AWS_REGION"

    log_info "Waiting for EBS CSI Driver to be active (may take 2-3 minutes)..."
    aws eks wait addon-active \
      --cluster-name "$CLUSTER_NAME" \
      --addon-name aws-ebs-csi-driver \
      --region "$AWS_REGION"

    log_success "EBS CSI Driver installed"
}

inject_terraform_outputs() {
    log_info "Injecting Terraform outputs into GitOps manifests..."

    if [ ! -f "$GITOPS_REPO_PATH/scripts/inject-terraform-outputs.sh" ]; then
        log_warning "inject-terraform-outputs.sh not found, skipping"
        return 0
    fi

    cd "$GITOPS_REPO_PATH"
    bash ./scripts/inject-terraform-outputs.sh
    cd - >/dev/null

    log_success "Terraform outputs injected into GitOps manifests"
}

configure_nodes_for_registry() {
    log_info "Configuring containerd on all nodes for private registry..."

    # Get bastion IP from Terraform
    cd "$TERRAFORM_PATH"
    BASTION_IP=$(terraform output -raw bastion_private_ip)
    REGISTRY_PORT=$(terraform output -raw local_registry_endpoint | cut -d: -f2)
    cd - >/dev/null

    log_info "Registry endpoint: $BASTION_IP:$REGISTRY_PORT"

    # Check if configure script exists
    if [ ! -f "./configure-nodes-registry.sh" ]; then
        log_warning "configure-nodes-registry.sh not found, skipping node configuration"
        log_info "Nodes will use containerd config from launch template"
        return 0
    fi

    # Run the configuration script
    bash ./configure-nodes-registry.sh "$BASTION_IP" "$REGISTRY_PORT"

    log_success "Nodes configured for registry access"
}

verify_registry_access() {
    log_info "Verifying local registry access..."

    # Get bastion IP from Terraform
    cd "$TERRAFORM_PATH"
    BASTION_IP=$(terraform output -raw bastion_private_ip)
    REGISTRY_PORT=$(terraform output -raw local_registry_endpoint | cut -d: -f2)
    cd - >/dev/null

    log_info "Registry endpoint: $BASTION_IP:$REGISTRY_PORT"

    # Get first node
    FIRST_NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

    log_info "Testing registry from node: $FIRST_NODE"

    # Test registry access
    if kubectl debug node/"$FIRST_NODE" -it --image=busybox -- wget -q -O- "http://$BASTION_IP:$REGISTRY_PORT/v2/_catalog" | grep -q "repositories"; then
        log_success "Registry access verified"
    else
        log_warning "Could not verify registry access (this may be normal for debug pod limitations)"
    fi
}

create_grafana_sealed_secret() {
    log_info "Creating Grafana admin sealed secret..."

    if [ ! -f "$GITOPS_REPO_PATH/create-grafana-sealed-secret.sh" ]; then
        log_warning "create-grafana-sealed-secret.sh not found, skipping"
        log_info "You'll need to create Grafana password manually later"
        return 0
    fi

    # Check if wave-2 directory exists
    if [ ! -d "$GITOPS_REPO_PATH/wave-2" ]; then
        log_warning "wave-2 directory not found - Grafana is deployed via Helm in wave-3"
        log_info "Grafana password can be set via Helm values in wave-3"
        log_info "Skipping sealed secret creation for now"
        return 0
    fi

    cd "$GITOPS_REPO_PATH"

    # Generate random password
    GRAFANA_PASSWORD=$(openssl rand -base64 32)
    log_info "Generated Grafana admin password (will be saved to grafanapass.txt)"

    # Save password to parent directory for user reference
    echo "Grafana Admin Credentials" > ../grafanapass.txt
    echo "=========================" >> ../grafanapass.txt
    echo "URL: https://grafana.ops.internal" >> ../grafanapass.txt
    echo "Username: admin" >> ../grafanapass.txt
    echo "Password: $GRAFANA_PASSWORD" >> ../grafanapass.txt
    echo "Generated: $(date)" >> ../grafanapass.txt

    # Create sealed secret non-interactively
    log_info "Creating sealed secret..."

    # Create temporary secret
    kubectl create secret generic grafana-admin-secret \
      --from-literal=admin-user=admin \
      --from-literal=admin-password="$GRAFANA_PASSWORD" \
      --namespace=monitoring \
      --dry-run=client \
      -o yaml > /tmp/grafana-secret.yaml

    # Seal the secret
    kubeseal --format=yaml \
      --controller-name=sealed-secrets-controller \
      --controller-namespace=kube-system \
      < /tmp/grafana-secret.yaml \
      > wave-2/grafana-sealed-secret.yaml 2>/dev/null || {
        log_warning "Failed to create sealed secret (controller may not be ready yet)"
        log_info "You can run create-grafana-sealed-secret.sh manually later"
        rm -f /tmp/grafana-secret.yaml
        cd - >/dev/null
        return 0
    }

    # Clean up
    rm -f /tmp/grafana-secret.yaml

    cd - >/dev/null
    log_success "Grafana sealed secret created and saved to wave-2/"
    log_info "Password saved to: $(pwd)/grafanapass.txt"
}

push_gitops_changes() {
    log_info "Committing and pushing GitOps changes to GitHub..."

    cd "$GITOPS_REPO_PATH"

    # Check if there are changes to commit
    if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        log_info "Detected changes in GitOps repository"

        # Show what changed
        log_info "Modified files:"
        git status --short

        # Stage all changes
        git add -A

        # Commit with descriptive message
        COMMIT_MSG="chore: inject terraform outputs and update bastion IP

Auto-generated commit from deploy-gitops-bootstrap.sh
- Updated bastion IP to new infrastructure
- Injected latest Terraform outputs
- Created Grafana sealed secret

Generated: $(date '+%Y-%m-%d %H:%M:%S')"

        git commit -m "$COMMIT_MSG"

        # Push to remote
        log_info "Pushing changes to GitHub..."
        if git push origin main 2>/dev/null || git push origin master 2>/dev/null; then
            log_success "Changes pushed to GitHub successfully"
        else
            log_error "Failed to push to GitHub"
            log_warning "You may need to push manually: cd $GITOPS_REPO_PATH && git push"
            read -p "Continue anyway? (yes/no): " continue_deploy
            if [ "$continue_deploy" != "yes" ]; then
                exit 1
            fi
        fi
    else
        log_info "No changes to commit in GitOps repository"
    fi

    cd - >/dev/null
}

deploy_root_app() {
    log_info "Deploying ArgoCD root application..."

    if [ ! -f "$GITOPS_REPO_PATH/apps/root-app.yaml" ]; then
        log_error "Root app manifest not found: $GITOPS_REPO_PATH/apps/root-app.yaml"
        exit 1
    fi

    kubectl apply -f "$GITOPS_REPO_PATH/apps/root-app.yaml"

    log_success "Root app deployed - ArgoCD will now sync all applications"
}

show_access_info() {
    echo ""
    echo "══════════════════════════════════════════════════════════════════════════════"
    log_success "GitOps Bootstrap Complete!"
    echo "══════════════════════════════════════════════════════════════════════════════"
    echo ""
    log_info "ArgoCD UI Access:"
    echo "  1. Get admin password:"
    echo "     kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    echo ""
    echo "  2. Port forward:"
    echo "     kubectl port-forward -n argocd svc/argocd-server 8080:443"
    echo ""
    echo "  3. Open browser: https://localhost:8080"
    echo "     Username: admin"
    echo "     Password: <from step 1>"
    echo ""
    log_info "Monitor deployment:"
    echo "  kubectl get applications -n argocd"
    echo "  kubectl get pods -A"
    echo ""
    log_info "Check sync waves:"
    echo "  Wave 0: Kyverno, Sealed Secrets, Policies"
    echo "  Wave 1: Traefik, Karpenter"
    echo "  Wave 2: Velero, Loki, Tempo"
    echo "  Wave 3: Prometheus Stack, Tools"
    echo "  Wave 4: Argo Rollouts, Image Updater"
    echo ""
    log_warning "IMPORTANT: Save sealed-secrets-master-key.yaml to a secure location!"
    echo "══════════════════════════════════════════════════════════════════════════════"
}

# ══════════════════════════════════════════════════════════════════════════════
# Main Execution
# ══════════════════════════════════════════════════════════════════════════════

main() {
    echo "══════════════════════════════════════════════════════════════════════════════"
    echo "                    EKS GitOps Bootstrap - Baseline Node Setup"
    echo "══════════════════════════════════════════════════════════════════════════════"
    echo ""

    check_prerequisites

    # ══════════════════════════════════════════════════════════════════════════════
    # PHASE 1: Prepare GitOps manifests and push to GitHub BEFORE installing ArgoCD
    # ══════════════════════════════════════════════════════════════════════════════
    log_info "═══ PHASE 1: Preparing GitOps Repository ═══"

    install_sealed_secrets
    inject_terraform_outputs
    create_grafana_sealed_secret
    push_gitops_changes

    log_success "GitOps repository prepared and pushed to GitHub"
    echo ""

    # ══════════════════════════════════════════════════════════════════════════════
    # PHASE 2: Install cluster components and deploy ArgoCD
    # ══════════════════════════════════════════════════════════════════════════════
    log_info "═══ PHASE 2: Installing Cluster Components ═══"

    install_ebs_csi_driver
    install_argocd
    update_argocd_placement

    # Git SSH key setup requires manual intervention
    log_info "Next step requires GitHub SSH key setup..."
    setup_git_repository_access

    configure_nodes_for_registry
    verify_registry_access
    deploy_root_app
    show_access_info
}

# Run main function
main "$@"
