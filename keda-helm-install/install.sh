### Add the KEDA Helm repository
helm repo add kedacore https://kedacore.github.io/charts

### Update the Helm repository
helm repo update

### Install KEDA in the 'keda' namespace
helm install keda kedacore/keda --namespace keda --create-namespace
