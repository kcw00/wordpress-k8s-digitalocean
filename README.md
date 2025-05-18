# wordpress-k8s-digitalocean

---

This repository provides a step-by-step guide on how to set up wordpress on your domain using digital ocean

---

Before starting to set up, you should install homebrew in your computer

If you havent' install homebrew yet, go to here: https://brew.sh/

If you have install homebrew, run commands below

### homebrew commands
```
brew doctor // check issues
brew update // check if it is outdated
brew upgrade // install it's latest package
```
---

## Installation

1. go to digitalocean and create an account
2. go to your control panel and click `Kuberbnetes`
   <img width="1512" alt="Screenshot 2025-03-08 at 13 02 37" src="https://github.com/user-attachments/assets/08e7e4fc-a184-4fe8-b49d-cce74f7222f7" />

3. create your cluster and download your config file when it is ready (it will take some times to be ready)
  <img width="1488" alt="Screenshot 2025-05-11 at 19 39 49" src="https://github.com/user-attachments/assets/2f9d8bff-1d91-4e17-9b2e-2be5cc4dc46f" />

5. install the ingress controller
   ```
     helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
     helm install my-nginx ingress-nginx/ingress-nginx
   ```
6. get kubectl
   ```
     brew install kubectl
   ```
7. type this command in the terminal before running kubernetes
    ```
      export KUBECONFIG=/Users/your-name/Downloads/[your_config_file]
    ```

    *  To find config file using terminal
        ```
          ls -lorth
        ```
---
## Usage

1. check nodes in your cluster `kubectl get node`
2. modify the domain of the new wordpress site in the manifest.yaml particularly in the ingress section
    ```
      spec:
        tls:
          - hosts:
              - www.chaewon.ca          # your domain name
            secretName: wordpress-tls   # cert will be stored here
        rules:
          - host: www.chaewon.ca       # your domain name
    ```
4. apply manifest.yaml to your kubernetes cluster `kubectl apply -f manifest.yaml`
5. get your ip address
   ```
     kubectl get svc -w // check 'EXTERNAL-IP' to find your ip address
   ```
6. point your dns to it: after getting the svc public ip address, apply it to the domain that you are working with
7. apply manifest-step2.yaml to your kubernetes cluster
   ```
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
    kubectl apply -f manifest-step2.yaml
   ```
8. go to your domain, and you will be able to see the Wordpress there
