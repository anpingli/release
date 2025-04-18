#!/bin/bash
echo "Enable Openshift-Logging in Cluster"

if [ -f "${SHARED_DIR}/proxy-conf.sh" ] ; then
  source "${SHARED_DIR}/proxy-conf.sh"
fi

function operators_ready()
{
    echo "# Verify if Operators are running"
    oc get csv -n openshift-logging |grep cluster-logging |wc -l

    oc get csv -n openshift-logging |grep -e "cluster-logging.*Succeeded" |wc -l
    if [[ $? ==  1 ]]; then
        echo "cluster-logging csv is not ready"
        oc get csv -n openshift-logging 
        exit 1
    fi

    oc get csv -n openshift-logging |grep -e "loki-operator.*Succeeded" |wc -l
    if [[ $? ==  1 ]]; then
        echo "cluster-logging csv is not ready"
        oc get csv -n openshift-logging 
        exit 1
    fi
}

function deploy_minio(){
    minio_ns="minio-logging-test"
    minio_secret="minio$(date +%s)"
    minio_svc="minio-service.${minio_ns}.svc:9000"

    echo "# Create minio for lokistack in ${minio_ns}"
    oc new-project $minio_ns || exit 1
    oc apply -f - <<EOF
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: minio-pv-claim
  namespace: ${minio_ns}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 40Gi
EOF
   oc apply -f - <<EOF
kind: Deployment
apiVersion: apps/v1
metadata:
  name: minio
  namespace: ${minio_ns}
spec:
  selector:
    matchLabels:
      app: minio
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: minio
    spec:
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: minio-pv-claim
      containers:
        - name: minio
          volumeMounts:
            - name: data
              mountPath: "/data"
          image: quay.io/openshifttest/minio:latest
          args:
            - server
            - /data
            - --console-address
            - ":9001"
          env:
            - name: MINIO_ACCESS_KEY
              value: "minio"
            - name: MINIO_SECRET_KEY
              value: "${minio_secret}"
          ports:
            - containerPort: 9000
          readinessProbe:
            httpGet:
              path: /minio/health/ready
              port: 9000
            initialDelaySeconds: 120
            periodSeconds: 20
          livenessProbe:
            httpGet:
              path: /minio/health/live
              port: 9000
            initialDelaySeconds: 120
            periodSeconds: 20
EOF

    oc apply -f - <<EOF
kind: Service
apiVersion: v1
metadata:
  name: minio-service
  namespace: ${minio_ns}
spec:
  ports:
    - port: 9000
      targetPort: 9000
      protocol: TCP
  selector:
    app: minio
EOF

wait pod is ready:

}

echo "deploy minio for lokistack"

echo "deploy lokistack"
oc apply -f <<EOF
---
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
spec:
  managementState: Managed
  size: 1x.demo
  storage:
    schemas:
      - effectiveDate: '2023-10-15'
        version: v13
    secret:
      name: s3-secret
      type: s3
  storageClassName: gp3-csi
  tenants:
    mode: openshift-logging
  rules:
    enabled: true
    selector:
      matchLabels:
        openshift.io/cluster-monitoring: 'true'
    namespaceSelector:
      matchLabels:
        openshift.io/cluster-monitoring: 'true'
EOF

wait until lokistack is ready 

echo "send logs to lokistack"

:wq

echo "lokistack is not ready"
exit 1
