# wordpress-k8s-digitalocean

---

This guide helps you deploy a WordPress site on a DigitalOcean Kubernetes Cluster with automatic HTTPS setup.

---
## ✅ Prerequisites

Make sure you have homebrew installed via [Homebrew](https://brew.sh/)

If you have install homebrew, run commands below

### homebrew commands
```bash
brew doctor                  # Check for any brew issues
brew update                  # Update Homebrew itself
brew upgrade                 # Upgrade all installed packages
brew install kubectl         # CLI for Kubernetes
brew install helm            # Package manager for Kubernetes
```
---

## Cluster Setup

1. Go to digitalocean and create an account
2. Go to your control panel and click `Kuberbnetes`
   <img width="1512" alt="Screenshot 2025-03-08 at 13 02 37" src="https://github.com/user-attachments/assets/08e7e4fc-a184-4fe8-b49d-cce74f7222f7" />

3. Create your cluster and download your config file when it is ready (it will take some times to be ready). This allows kubectl to connect to your cluster.
  <img width="1488" alt="Screenshot 2025-05-11 at 19 39 49" src="https://github.com/user-attachments/assets/2f9d8bff-1d91-4e17-9b2e-2be5cc4dc46f" />

4. Get kubectl
   ```bash
     brew install kubectl
   ```
5. Type this command in the terminal before running kubernetes
    ```bash
      export KUBECONFIG=/Users/your-name/Downloads/[your_config_file]
    ```

    *  To find config file in terminal, type this
        ```bash
          ls -lorth
        ```
6. To confirm connection
   ```bash
   kubectl get nodes
   ```
7. Install NGINX ingress controller
   ```
   helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
   helm install nginx-ingress ingress-nginx/ingress-nginx \
     --namespace ingress-nginx --create-namespace \
     --set controller.ingressClassResource.name=nginx \
     --set controller.ingressClass=nginx
   ```
---
## Usage

1. Check nodes in your cluster 
   ```bash
    kubectl get nodes  # show cluster nodes -> the name should match with your node pools in k8s cluster
   ```
2. Modify the your domain in the `manifest.yaml` particularly in the ingress section
   ```yaml
         spec:
           tls:
             - hosts:
                 - www.chaewon.ca          # your domain name
               secretName: wordpress-tls   # cert will be stored here
           rules:
             - host: www.chaewon.ca       # your domain name
   ```
3. Apply manifest.yaml to your kubernetes cluster
      ```bash
        kubectl apply -f manifest.yaml
      ```
4. Get your ip address
      ```bash
         kubectl get svc -n ingress-nginx      # check 'EXTERNAL-IP' to find your ip address
      ```
5. Point your DNS to your IP address: after getting the svc public ip address, apply it to the domain that you are working with  
    This is an example in Digital Ocean.
   
   | Type  | Hostname    | Value    | TTL     |
   |-------|-------------|----------|---------|
   |  A    | www         | your-ip-address  | Defalut |

        
6. Setup HTTPS with cert-manager
   ```bash
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
    kubectl apply -f manifest-step2.yaml
   ```
7. Check TLS is working
   ```bash
   kubectl describe certificate wordpress-tls
   ```
    if it works fine, you will see
   ```bash
   Message: Certificate is up to date and has not expired
   Status: True
   ```
8. Go to your domain, and you will be able to see the Wordpress there
