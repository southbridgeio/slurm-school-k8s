#/bin/sh

kubectl create ns dev
kubectl create ns prod
kubectl -n dev run backend-dev --image nginx
kubectl -n prod run backend-prod --image nginx
kubectl -n dev create secret generic db --from-literal=dbpassword=dev
kubectl -n prod create secret generic db --from-literal=dbpassword=production
kubectl -n dev create cm config --from-file=dev=prepare.sh
kubectl -n prod create cm config --from-file=prod=prepare.sh
