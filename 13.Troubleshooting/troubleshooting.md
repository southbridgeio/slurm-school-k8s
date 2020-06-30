# все сломалось...

в браузере hello.s000001.edu.slurm.io показывает `default backend - 404`
Просили помочь знакомого студента - он не смог.

# нет доступа у админа
заходим на master-1.s000001

```kubectl get nodes
The connection to the server localhost:8080 was refused - did you specify the right host or port?
```
## что случилось - какие мысли у зала ?

### решение простое
```
mkdir -p ~/.kube
cp /etc/kubernetes/admin.conf ~/.kube/config
```

### если простое решение не сработало

```
# проверяем что API запущен, смотрим в его логи
docker ps
docker logs

# Если ошибок нет правим манифест и включаем опцию     - --insecure-port=8080
# ждем пока кублет отрестартит API сервер, а можно и самому стопнуть контейнер
# заработало, но это доступ без авторизации, правда только с localhost
kubectl get nodes 

netstat -ntpl 
tcp        0      0 127.0.0.1:8080          0.0.0.0:*               LISTEN      5532/kube-apiserver

# Смотрим в кластер:
kubectl get node
kubectl get pod -A

# Восстанавливаем-создаем админа, который будет авторизовываться по токену

kubectl create serviceaccount admin --namespace kube-system 
kubectl create clusterrolebinding admin --namespace kube-system --clusterrole cluster-admin --serviceaccount kube-system:admin
kubectl get secret $(kubectl get serviceaccount --namespace kube-system admin -o jsonpath='{.secrets[].name}') --namespace kube-system -o jsonpath='{.data.token}' | base64 -d

# Смотрим и видим localhost:8080 - который мы только что открыли
kubectl cluster-info
# решаем использовать адрес сервера - 172.16.0.2
# прописываем сервер
kubectl config set-cluster my   --embed-certs=true   --server=https://172.16.0.2:6443   --certificate-authority=/etc/kubernetes/pki/ca.crt
# прописываем креды
kubectl config set-credentials admin --token=$(kubectl get secret $(kubectl get serviceaccount --namespace kube-system admin -o jsonpath='{.secrets[].name}') --namespace kube-system -o jsonpath='{.data.token}' | base64 -d )

# прописываем контекст
kubectl config set-context my-admin --cluster=my --user=admin
# Начинаем использовать
kubectl config use-context my-admin
```

# kubectl get nodes 

```
NAME                        STATUS     ROLES    AGE   VERSION
master-1.s000001.slurm.io   Ready      master   32m   v1.15.3
master-2.s000001.slurm.io   Ready      master   32m   v1.15.3
master-3.s000001.slurm.io   NotReady   master   31m   v1.15.3
node-1.s000001.slurm.io     Ready      <none>   30m   v1.15.3
node-2.s000001.slurm.io     NotReady   <none>   30m   v1.15.3
```

Смотрим describe
```
kubectl describe node master-3.s000001.slurm.io

kubectl describe node node-1.s000001.slurm.io

# Kubelet stopped posting node status.

kubectl get pod -A -o wide
```
Видим что поды с node-2 в терминейтед, а на master-3 работают. Почему ? 
Потому что на мастере-3 остались только поды, запущенные как статик поды и как даемон сеты. первыми API сервер не управляет, вторые с узла никуда не эвакуируются.

Пошли разбираться - начнем с контрол плейна
```
ssh master-3.s000001
systemctl status kubelet 
docker ps
# кто-то выключил кублет )

systemctl enable --now kubelet
systemctl status kubelet 
# смотрим статусы узлов
```

Далее идем на узел node-2
```
ssh master-3.s000001
systemctl status kubelet 
docker ps
systemctl restart kubelet 
systemctl status kubelet 
less /var/log/kubernetes.log

Nov  8 14:46:15 node-2 kubelet: F1108 14:46:15.577389   12914 server.go:273] failed to run Kubelet: failed to create kubelet: misconfiguration: kubelet cgroup driver: "cgroupfs" is different from docker cgroup driver: "systemd"

Лезем в гугл, читаем, думаем.
Правим /var/lib/kubelet/config.yaml 
# не помогло

исследуем systemd файлы, находим флаги кубадма, правим там - запускаем
```

Смотрим поды, видим что все поднялось, кроме шедулера на мастер-1, но все работает, потому что есть еще два шедулера.
смотрим ему в логи видим unknown flag: --insecure-port 80.
```
kubectl -n kube-system logs kube-scheduler-master-1.s000001.slurm.io
```

Правим манифесты статик пода шедулера.

Далее видим, что часть статик подов, запущенных на master-2 имеют статус OutOfCPU, а под flannel в статусе Pending.
Смотрим описание узла
```
describe node master-2

Capacity:
 cpu:                1
 ephemeral-storage:  9765120Ki
 hugepages-1Gi:      0
 hugepages-2Mi:      0
 memory:             4039688Ki
 pods:               110
Allocatable:
 cpu:                0
 ephemeral-storage:  9765120Ki
 hugepages-1Gi:      0
 hugepages-2Mi:      0
 memory:             893960Ki
 pods:               110
```

Видим в наличии 1 ядро, но свободно к использованию 0.
Идем разбираться на master-2.

```
ps ax | grep kubelet

 4722 ?        Ssl    2:31 /usr/bin/kubelet --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf --config=/var/lib/kubelet/config.yaml --cgroup-driver=systemd --network-plugin=cni --pod-infra-container-image=k8s.gcr.io/pause:3.1 --eviction-hard=memory.available<1.5Gi --eviction-minimum-reclaim=memory.available=2.5Gi --eviction-max-pod-grace-period=30 --system-reserved=memory=1.5Gi,cpu=1
 
```

Ищем где опции system-reserved устанавливаются system-reserved=memory=1.5Gi,cpu=1 и правим-удаляем

```
vi /etc/sysconfig/kubelet
systemctl restart kubelet
```


уфф. вроде все системное поднялось, теперь можно занятся самим приложением.

```
kubectl -n hello get all

pod/my-deployment-b5f64ff55-tmhms   0/1     ImagePullBackOff   0          107m
```

Правим тег, вроде все заработало, curl работает, но в браузере не открывается, идем смотреть ингрессы

kubectl get ing
my-ingress   hello.s000001.edu.slurm.io1             80      142m

Правим, смотрим в браузер - скачивается файл, не отдается mime type.
Смотрим в логи пода, в конфиг мап, правим запятую
убиваем под.

## Вопрос. что будет если узел на котором находится под упадет ?
Узел будет тупить 5 минут - пробуемс выключить его и засечь время
```
 while true; do curl http://hello.s000001.edu.slurm.io; sleep 1; echo $RANDOM; done

```
git
```
kubectl scale deployment.apps/my-deployment --replicas 2 --n hello
```
