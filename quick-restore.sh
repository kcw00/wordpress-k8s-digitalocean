#!/bin/bash
set -e

echo "=========================================="
echo "WordPress Kubernetes Quick Restore"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check kubectl connection
echo -e "${YELLOW}Checking cluster connection...${NC}"
if ! kubectl get nodes &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster"
    echo "Please set KUBECONFIG: export KUBECONFIG=/path/to/your/kubeconfig.yaml"
    exit 1
fi
echo -e "${GREEN}✓ Connected to cluster${NC}"
echo ""

# Install NGINX Ingress
echo -e "${YELLOW}Installing NGINX Ingress Controller...${NC}"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.ingressClassResource.name=nginx \
  --set controller.ingressClass=nginx || echo "Ingress already installed"
echo -e "${GREEN}✓ NGINX Ingress installed${NC}"
echo ""

# Wait for external IP
echo -e "${YELLOW}Waiting for external IP (this may take 2-3 minutes)...${NC}"
while [ -z "$(kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)" ]; do
    echo -n "."
    sleep 5
done
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo ""
echo -e "${GREEN}✓ External IP assigned: $EXTERNAL_IP${NC}"
echo ""

# Deploy WordPress and MySQL
echo -e "${YELLOW}Deploying WordPress and MySQL...${NC}"
kubectl apply -f manifest.yaml
echo -e "${GREEN}✓ Resources created${NC}"
echo ""

# Wait for pods
echo -e "${YELLOW}Waiting for pods to be ready (this may take 2-3 minutes)...${NC}"
kubectl wait --for=condition=ready pod -l app=mysql --timeout=300s
kubectl wait --for=condition=ready pod -l app=wordpress --timeout=300s
echo -e "${GREEN}✓ Pods are running${NC}"
echo ""

# Get pod names
MYSQL_POD=$(kubectl get pods -l app=mysql -o jsonpath='{.items[0].metadata.name}')
WP_POD=$(kubectl get pods -l app=wordpress -o jsonpath='{.items[0].metadata.name}')
echo "MySQL pod: $MYSQL_POD"
echo "WordPress pod: $WP_POD"
echo ""

# Restore database
if [ -f ~/wordpress-backup-jan2025/database/wordpress-db-20260112_final.sql ]; then
    echo -e "${YELLOW}Restoring database...${NC}"
    # Use root user to avoid privilege errors
    kubectl exec -i $MYSQL_POD -- mysql -u root -pmyrootpassword wordpress < ~/wordpress-backup-jan2025/database/wordpress-db-20260112_final.sql 2>&1 | grep -v "Warning"
    echo -e "${GREEN}✓ Database restored${NC}"
    echo ""
else
    echo -e "${YELLOW}⚠ Database backup not found, skipping...${NC}"
    echo ""
fi

# Restore wp-content
if [ -f ~/wordpress-backup-jan2025/wp-content/wp-content-20260112_130331.tar.gz ]; then
    echo -e "${YELLOW}Restoring wp-content...${NC}"
    cd ~/wordpress-backup-jan2025/wp-content
    rm -rf var 2>/dev/null || true
    tar xzf wp-content-20260112_130331.tar.gz
    cd -

    kubectl cp ~/wordpress-backup-jan2025/wp-content/var/www/html/wp-content $WP_POD:/var/www/html/
    kubectl exec $WP_POD -- chown -R www-data:www-data /var/www/html/wp-content
    kubectl exec $WP_POD -- chmod -R 755 /var/www/html/wp-content
    echo -e "${GREEN}✓ wp-content restored${NC}"
    echo ""

    # Restart WordPress pod
    echo -e "${YELLOW}Restarting WordPress pod...${NC}"
    kubectl delete pod $WP_POD
    kubectl wait --for=condition=ready pod -l app=wordpress --timeout=120s
    echo -e "${GREEN}✓ WordPress restarted${NC}"
    echo ""
else
    echo -e "${YELLOW}⚠ wp-content backup not found, skipping...${NC}"
    echo ""
fi

# Install cert-manager
echo -e "${YELLOW}Installing cert-manager...${NC}"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
echo -e "${GREEN}✓ cert-manager installed${NC}"
echo ""

# Wait for cert-manager
echo -e "${YELLOW}Waiting for cert-manager to be ready...${NC}"
sleep 30
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s 2>/dev/null || echo "Still initializing..."
echo -e "${GREEN}✓ cert-manager ready${NC}"
echo ""

# Apply ClusterIssuer
echo -e "${YELLOW}Configuring Let's Encrypt...${NC}"
kubectl apply -f manifest-step2.yaml
echo -e "${GREEN}✓ ClusterIssuer created${NC}"
echo ""

# Final status
echo "=========================================="
echo -e "${GREEN}RESTORATION COMPLETE!${NC}"
echo "=========================================="
echo ""
echo "Your WordPress site is being deployed at:"
echo "  IP Address: $EXTERNAL_IP"
echo "  Domain: www.chaewon.ca"
echo ""
echo "NEXT STEPS:"
echo "1. Update DNS A record for 'www.chaewon.ca' to: $EXTERNAL_IP"
echo "   IMPORTANT: Go to Cloudflare (NOT DigitalOcean):"
echo "   https://dash.cloudflare.com"
echo "   Edit 'www' A record, set IP to $EXTERNAL_IP"
echo "   Turn proxy OFF (grey cloud) for certificate issuance"
echo ""
echo "2. Wait 5-10 minutes for certificate to be issued"
echo "   Check status: kubectl describe certificate wordpress-tls"
echo ""
echo "3. Visit your site: https://www.chaewon.ca"
echo ""
echo "USEFUL COMMANDS:"
echo "  kubectl get pods                    # View pods"
echo "  kubectl get certificate             # Check SSL certificate"
echo "  kubectl logs -l app=wordpress       # View WordPress logs"
echo "  kubectl get ingress                 # View ingress configuration"
echo ""
