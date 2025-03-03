# keda-poc

## Step 1: Add and Install KEDA using Helm
KEDA (Kubernetes Event-Driven Autoscaling) helps scale workloads in Kubernetes. To install KEDA using Helm, run the following commands:

```bash
### Add the KEDA Helm repository
helm repo add kedacore https://kedacore.github.io/charts

### Update the Helm repository
helm repo update

### Install KEDA in the 'keda' namespace
helm install keda kedacore/keda --namespace keda --create-namespace
```

## Step 2: Apply RabbitMQ Secret, Deployment, and Service
After installing KEDA, the next step is to configure RabbitMQ by applying the necessary Kubernetes resources:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rabbitmq-secret
type: Opaque
data:
  username: dXNlcgo=
  password: cGFzc3dvcmQK
  RABBITMQ_MANAGEMENT_URL: aHR0cDovL3VzZXI6cGFzc3dvcmRAcmFiYml0bXEuZGVmYXVsdC5zdmMuY2x1c3Rlci5sb2NhbDoxNTY3Mi8K

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rabbitmq
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rabbitmq
  template:
    metadata:
      labels:
        app: rabbitmq
    spec:
      containers:
        - name: rabbitmq
          image: rabbitmq:3.9-management
          ports:
            - containerPort: 5672
            - containerPort: 15672
          env:
            - name: RABBITMQ_DEFAULT_USER
              valueFrom:
                secretKeyRef:
                  name: rabbitmq-secret
                  key: username
            - name: RABBITMQ_DEFAULT_PASS
              valueFrom:
                secretKeyRef:
                  name: rabbitmq-secret
                  key: password

---
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq
spec:
  selector:
    app: rabbitmq
  ports:
    - protocol: TCP
      port: 5672
      targetPort: 5672
      name: rabbitmq
    - protocol: TCP
      port: 15672
      targetPort: 15672
      name: management
  type: ClusterIP
```
## Step 3
