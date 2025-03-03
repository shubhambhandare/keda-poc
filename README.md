# keda-poc

## Overview
This Proof of Concept (**PoC**) demonstrates how to use **KEDA (Kubernetes Event-Driven Autoscaling)** to dynamically scale worker pods based on the number of messages in a **RabbitMQ queue**.  

### **How It Works**  
- We have a **Flask-based worker application**, which serves **two roles**:  
  1. **Sending messages** to a RabbitMQ queue.  
  2. **Consuming and acknowledging messages** from the queue.  
- As the **number of messages in the queue increases**, **KEDA automatically scales up** the worker pods to handle the load.  
- When messages are **processed (acknowledged)**, the queue size decreases, and **KEDA scales down** the worker pods accordingly.  

### **Python Scripts for PoC**  
To simulate load and test auto-scaling behavior, we have written two Python scripts:  

1. **`loadgen.py`** - Sends messages to RabbitMQ continuously to increase queue size.  
2. **`consume_faster.py`** - Consumes messages quickly to reduce queue size.  

This setup ensures **efficient resource utilization** by dynamically adjusting the number of worker pods based on real-time message load in RabbitMQ.


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

## Step 2: Deploy RabbitMQ Secret, Deployment, and Service
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

```bash
kubectl apply -f rabbitmq.yaml
```

## Step 3: Set Up RabbitMQ Permissions
Run the following command to create a new RabbitMQ user and set permissions:  

```bash
kubectl exec -it deploy/rabbitmq -- bash -c "rabbitmqctl add_user user password && rabbitmqctl set_user_tags user administrator && rabbitmqctl set_permissions -p / user '.*' '.*' '.*'"
```

## Step 4: Deploy Worker Application - Deployment, Service and ConfigMap (Flask FrontEnd Application)
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  requirements.txt: |
    Flask
    pika
  app.py: |
    from flask import Flask
    import pika
    import os
    import time
    import threading

    app = Flask(__name__)

    # RabbitMQ configuration
    rabbitmq_host = os.environ.get('RABBITMQ_HOST', 'rabbitmq')
    rabbitmq_queue = os.environ.get('RABBITMQ_QUEUE', 'myqueue')

    @app.route('/process', methods=['POST'])
    def process_message():
        """Processes a message by connecting to RabbitMQ and declaring a queue."""
        try:
            connection = pika.BlockingConnection(pika.ConnectionParameters(host=rabbitmq_host))
            channel = connection.channel()
            channel.queue_declare(queue=rabbitmq_queue, durable=True)

            time.sleep(2)  # Simulating processing delay

            return "Message processed!", 200
        except Exception as e:
            return f"Error: {e}", 500

    def consume_messages():
        """Consumes messages from the RabbitMQ queue in a separate thread."""
        try:
            connection = pika.BlockingConnection(pika.ConnectionParameters(host=rabbitmq_host))
            channel = connection.channel()
            channel.queue_declare(queue=rabbitmq_queue)

            def callback(ch, method, properties, body):
                print(f" [x] Received {body.decode()}")
                time.sleep(2)  # Simulating message processing delay
                ch.basic_ack(delivery_tag=method.delivery_tag)

            channel.basic_consume(queue=rabbitmq_queue, on_message_callback=callback)

            print(' [*] Waiting for messages. To exit press CTRL+C')
            channel.start_consuming()
        except Exception as e:
            print(f"Consumer error: {e}")

    if __name__ == '__main__':
        consumer_thread = threading.Thread(target=consume_messages, daemon=True)
        consumer_thread.start()
        app.run(debug=True, host='0.0.0.0', port=5000)
  loadgen.py: |
    import pika
    import os
    import time

    RABBITMQ_HOST = os.getenv("RABBITMQ_SERVICE_HOST", "rabbitmq")
    RABBITMQ_USER = os.getenv("RABBITMQ_USER", "user")
    RABBITMQ_PASSWORD = os.getenv("RABBITMQ_PASSWORD", "password")
    QUEUE_NAME = "myqueue"

    credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASSWORD)
    connection = pika.BlockingConnection(pika.ConnectionParameters(host=RABBITMQ_HOST, credentials=credentials))
    channel = connection.channel()
    channel.queue_declare(queue=QUEUE_NAME)

    counter = 1
    while True:
        message = f"Message {counter}"
        channel.basic_publish(exchange="", routing_key=QUEUE_NAME, body=message)
        print(f"Sent: {message}")
        counter += 1
        time.sleep(0.5)
  consume_faster.py: |
    import pika
    import os
    import time

    RABBITMQ_HOST = os.getenv("RABBITMQ_SERVICE_HOST", "rabbitmq")
    RABBITMQ_USER = os.getenv("RABBITMQ_USER", "user")
    RABBITMQ_PASSWORD = os.getenv("RABBITMQ_PASSWORD", "password")
    QUEUE_NAME = "myqueue"

    credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASSWORD)
    connection = pika.BlockingConnection(pika.ConnectionParameters(host=RABBITMQ_HOST, credentials=credentials))
    channel = connection.channel()

    def callback(ch, method, properties, body):
        print(f"Received: {body}")
        ch.basic_ack(delivery_tag=method.delivery_tag)  # Acknowledge message
        time.sleep(0.1)  # Adjust sleep time to process faster

    channel.basic_consume(queue=QUEUE_NAME, on_message_callback=callback)
    print("Waiting for messages...")
    channel.start_consuming()

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: worker
  template:
    metadata:
      labels:
        app: worker
    spec:
      initContainers:
        - name: init-wait-for-rabbitmq
          image: busybox
          command: ['sh', '-c', 'until nc -z rabbitmq 5672; do echo "waiting for rabbitmq"; sleep 2; done;']
      containers:
        - name: worker-app
          image: python:3.9-slim-buster
          imagePullPolicy: Always
          command: ["/bin/sh", "-c", "pip install -r /app/requirements.txt && python app.py"]
          env:
            - name: RABBITMQ_USER
              valueFrom:
                secretKeyRef:
                  name: rabbitmq-secret
                  key: username
            - name: RABBITMQ_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: rabbitmq-secret
                  key: password
          volumeMounts:
            - name: app-volume
              mountPath: /app
          workingDir: /app
      volumes:
        - name: app-volume
          configMap:
            name: app-config

---
apiVersion: v1
kind: Service
metadata:
  name: worker-service
spec:
  selector:
    app: worker
  ports:
    - protocol: TCP
      port: 5000
      targetPort: 5000
  type: ClusterIP
```

```bash
kubectl apply -f worker.yaml
```

## Step 5: Configure KEDA for Auto-Scaling - ScaledObjects and TriggerAuthentication
```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: keda-trigger-auth-rabbitmq
spec:
  secretTargetRef:
    - parameter: host
      name: rabbitmq-secret
      key: RABBITMQ_MANAGEMENT_URL

---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: worker-deployment-scaledobject
spec:
  scaleTargetRef:
    name: worker-deployment
  pollingInterval: 30
  cooldownPeriod: 60
  minReplicaCount: 1
  maxReplicaCount: 10
  triggers:
    - type: rabbitmq
      metadata:
        protocol: http
        queueName: ^myqueue$
        mode: QueueLength
        value: "5"
        useRegex: "true"
        operation: max
      authenticationRef:
        name: keda-trigger-auth-rabbitmq
```

```bash
kubectl apply -f scaledobjects.yaml
```

## Step 6: Test the KEDA autoscaling
#### Send Messages to Increase Queue & Scale Up Pods
```bash
kubectl exec -it deploy/worker-deployment -- python loadgen.py
```

This will start sending messages to application, as the queue length grows, KEDA will automatically increase the number of pods accordingly.

#### Consume Messages to Decrease Queue & Scale Down Pods
```bash
kubectl exec -it deploy/worker-deployment -- python consume_faster.py
```

This will start consuming messages from RabbitMQ, as the queue length reduces, KEDA will scale down the number of worker pods accordingly.

