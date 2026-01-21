# WordPress K8s Restoration - Quick Reference Guide

**Last successful restoration:** January 20, 2026
**Site:** https://www.chaewon.ca
**Backup location:** `~/wordpress-backup-jan2025/`

---

## Prerequisites

- DigitalOcean account
- Local backup in `~/wordpress-backup-jan2025/`
- `kubectl` and `helm` installed via Homebrew

---

## Step-by-Step Restoration Process

### 1. Create New Kubernetes Cluster on DigitalOcean

**Via Web Console:**
1. Go to https://cloud.digitalocean.com/kubernetes
2. Click "Create Cluster"
3. Configuration used:
   - Region: SFO3
   - Node pool: 2 nodes × Basic (1 vCPU, 2GB RAM, 50GB storage) = $24/month
   - Kubernetes version: Latest stable
4. Wait ~5 minutes for cluster to be ready
5. **Download the kubeconfig file**

---

### 2. Connect to Cluster

```bash
# Set kubeconfig (update filename to match your download)
export KUBECONFIG=~/Downloads/k8s-1-34-1-do-2-sfo3-XXXXXXXXX-kubeconfig.yaml

# Verify connection
kubectl get nodes

# You should see 2 nodes in Ready status
```

**IMPORTANT:** Add this to `~/.zshrc` for persistence:
```bash
echo 'export KUBECONFIG=~/Downloads/[your-config].yaml' >> ~/.zshrc
```

---

### 3. Install NGINX Ingress Controller

```bash
# Add Helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install NGINX Ingress
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.ingressClassResource.name=nginx \
  --set controller.ingressClass=nginx

# Wait for external IP (takes 2-3 minutes)
kubectl get svc -n ingress-nginx --watch
```

**Note the EXTERNAL-IP** when it appears (not `<pending>`)

---

### 4. Deploy WordPress and MySQL

```bash
cd ~/wordpress-k8s-digitalocean

# Apply manifest
kubectl apply -f manifest.yaml

# Wait for pods (takes 2-3 minutes)
kubectl get pods --watch

# Press Ctrl+C when both pods show Running status
```

---

### 5. Restore Database

```bash
# Get MySQL pod name
MYSQL_POD=$(kubectl get pods -l app=mysql -o jsonpath='{.items[0].metadata.name}')
echo "MySQL pod: $MYSQL_POD"

# Restore database (use root user to avoid permission issues)
kubectl exec -i $MYSQL_POD -- mysql -u root -pmyrootpassword wordpress \
  < ~/wordpress-backup-jan2025/database/wordpress-db-20260112_final.sql

# Verify tables were restored
kubectl exec $MYSQL_POD -- mysql -u wordpress -pmywordpresspass \
  -e "USE wordpress; SHOW TABLES;" 2>/dev/null

# Should see: wp_posts, wp_users, wp_options, etc.
```

**Important:** Use `root` user (not `wordpress` user) to avoid privilege errors

---

### 6. Restore WordPress Content (wp-content)

```bash
# Get WordPress pod name
WP_POD=$(kubectl get pods -l app=wordpress -o jsonpath='{.items[0].metadata.name}')
echo "WordPress pod: $WP_POD"

# Extract backup
cd ~/wordpress-backup-jan2025/wp-content
rm -rf var 2>/dev/null || true
tar xzf wp-content-20260112_130331.tar.gz

# Copy to pod
kubectl cp ./var/www/html/wp-content $WP_POD:/var/www/html/

# Fix permissions
kubectl exec $WP_POD -- chown -R www-data:www-data /var/www/html/wp-content
kubectl exec $WP_POD -- chmod -R 755 /var/www/html/wp-content

# Restart WordPress pod
kubectl delete pod $WP_POD
kubectl wait --for=condition=ready pod -l app=wordpress --timeout=120s
```

---

### 7. Update DNS in Cloudflare

**Critical:** Your domain uses Cloudflare DNS, not DigitalOcean DNS!

1. Get the new load balancer IP:
   ```bash
   kubectl get svc -n ingress-nginx
   ```
   Look for `EXTERNAL-IP` of `nginx-ingress-ingress-nginx-controller`

2. Update Cloudflare:
   - Go to https://dash.cloudflare.com
   - Select domain: `chaewon.ca`
   - Click "DNS" in left menu
   - Edit the `www` A record:
     - **IP Address:** [Your new EXTERNAL-IP]
     - **Proxy status:** Click orange cloud to make it **GREY (DNS only)**
   - Save changes

**Why DNS only?** Let's Encrypt needs direct access to issue the SSL certificate.

---

### 8. Install cert-manager and Configure HTTPS

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

# Wait for cert-manager to be ready (30 seconds)
sleep 30
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/instance=cert-manager \
  -n cert-manager \
  --timeout=300s

# Apply ClusterIssuer for Let's Encrypt
kubectl apply -f manifest-step2.yaml

# Check certificate status (takes 5-10 minutes)
kubectl get certificate
kubectl describe certificate wordpress-tls
```

Look for:
```
Status: True
Message: Certificate is up to date and has not expired
```

---

### 9. Verify Site is Working

```bash
# Check DNS propagation
dig www.chaewon.ca +short
# Should show your new IP

# Test HTTPS access
curl -I https://www.chaewon.ca
# Should return HTTP/2 200 or 302

# Open in browser
open https://www.chaewon.ca
```

Your site should now be live with HTTPS! ✓

---

### 10. (Optional) Re-enable Cloudflare Proxy

Once the certificate is issued and site is working:

1. Go back to Cloudflare DNS settings
2. Edit the `www` A record
3. Click the grey cloud to make it **ORANGE (Proxied)**
4. This enables Cloudflare CDN, DDoS protection, etc.

---

## Important Files & Credentials

### Backup Files
- Database: `~/wordpress-backup-jan2025/database/wordpress-db-20260112_final.sql`
- Content: `~/wordpress-backup-jan2025/wp-content/wp-content-20260112_130331.tar.gz`
- K8s configs: `~/wordpress-backup-jan2025/k8s-configs/`

### Passwords (stored in manifest.yaml as base64)
```bash
# Decode passwords if needed:
echo "bXlyb290cGFzc3dvcmQ=" | base64 -d  # myrootpassword
echo "bXl3b3JkcHJlc3NwYXNz" | base64 -d  # mywordpresspass
```

- MySQL root password: `myrootpassword`
- MySQL wordpress password: `mywordpresspass`

### Domain Configuration
- Domain: `chaewon.ca`
- DNS Provider: **Cloudflare** (NOT DigitalOcean)
- Nameservers: `elle.ns.cloudflare.com`, `yevgen.ns.cloudflare.com`

---

## Common Issues & Solutions

### Issue: kubectl can't connect to cluster
**Solution:**
```bash
export KUBECONFIG=~/Downloads/[your-new-config].yaml
kubectl get nodes
```

### Issue: Site shows "Connection timed out" (Error 522)
**Cause:** DNS not updated or Cloudflare proxy is ON
**Solution:**
1. Update DNS in Cloudflare (not DigitalOcean)
2. Turn proxy OFF (grey cloud) while certificate is being issued
3. Wait 2-5 minutes for DNS propagation

### Issue: Certificate not issuing
**Check status:**
```bash
kubectl describe certificate wordpress-tls
kubectl logs -n cert-manager -l app=cert-manager --tail=50
```
**Common cause:** Cloudflare proxy is ON - must be DNS only (grey cloud)

### Issue: Database restore shows privilege errors
**Solution:** Use `root` user instead of `wordpress` user:
```bash
kubectl exec -i $MYSQL_POD -- mysql -u root -pmyrootpassword wordpress < backup.sql
```

### Issue: WordPress shows installation screen
**Cause:** Database not restored or empty
**Solution:** Check database tables exist:
```bash
kubectl exec $MYSQL_POD -- mysql -u wordpress -pmywordpresspass \
  -e "USE wordpress; SHOW TABLES;"
```
If empty, restore database again using root user.

### Issue: Images not loading
**Cause:** wp-content not restored or wrong permissions
**Solution:**
```bash
kubectl exec $WP_POD -- ls -la /var/www/html/wp-content/uploads/
kubectl exec $WP_POD -- chown -R www-data:www-data /var/www/html/wp-content
```

---

## Useful Commands

### Monitoring
```bash
# View all resources
kubectl get all

# Check pods with logs
kubectl get pods
kubectl logs -l app=wordpress --tail=50 -f
kubectl logs -l app=mysql --tail=50 -f

# Check persistent volumes
kubectl get pvc

# Check ingress
kubectl get ingress
kubectl describe ingress wordpress-ingress

# Check certificate
kubectl get certificate
kubectl describe certificate wordpress-tls

# Get external IP
kubectl get svc -n ingress-nginx
```

### Troubleshooting
```bash
# Restart WordPress
kubectl rollout restart deployment wordpress

# Restart MySQL
kubectl rollout restart deployment mysql

# Access WordPress pod shell
kubectl exec -it $WP_POD -- bash

# Access MySQL directly
kubectl exec -it $MYSQL_POD -- mysql -u wordpress -pmywordpresspass wordpress

# Check WordPress files
kubectl exec $WP_POD -- ls -la /var/www/html/

# Check database connectivity from WordPress
kubectl exec $WP_POD -- ping mysql
```

### Cleanup (if starting over)
```bash
# Delete everything
kubectl delete -f manifest.yaml
kubectl delete -f manifest-step2.yaml

# Delete PVCs (CAUTION: destroys data!)
kubectl delete pvc mysql-pvc wordpress-pvc

# Then redeploy from step 4
```

---

## Cost Breakdown

**Monthly costs:**
- Kubernetes cluster (2 nodes @ $12/month): $24
- Load Balancer: $12
- Block storage (20GB PVCs): ~$2
- **Total: ~$38/month**

**To reduce costs:**
- Scale to 1 node if traffic is low
- Delete cluster when not in use
- Use snapshots for long-term storage

---

## Next Steps After Restoration

1. **Create new backup immediately**
2. **Test all functionality:**
   - Login to wp-admin
   - Check all pages load
   - Verify images display
   - Test contact forms
   - Check plugins are active

3. **Set up monitoring:**
   - UptimeRobot (free tier)
   - DigitalOcean monitoring

4. **Security:**
   - Update WordPress core, themes, plugins
   - Install Wordfence or similar security plugin
   - Enable 2FA for wp-admin

5. **Performance:**
   - Install caching plugin (W3 Total Cache)
   - Consider CDN (Cloudflare is already in front)

6. **Regular backups:**
   - Set up automated backups (weekly)
   - Store in multiple locations (cloud + local)

---

## Quick Restoration (All-in-One Script)

For future use, the `quick-restore.sh` script automates most steps:

```bash
export KUBECONFIG=~/Downloads/[your-config].yaml
cd ~/wordpress-k8s-digitalocean
./quick-restore.sh
```

**Note:** Still requires manual DNS update in Cloudflare

---

## Additional Resources

- [DigitalOcean Kubernetes Docs](https://docs.digitalocean.com/products/kubernetes/)
- [WordPress Codex](https://wordpress.org/support/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/home/)

---

**Last updated:** January 20, 2026
**Restoration time:** ~45 minutes
**Success rate:** 100% when following this guide
