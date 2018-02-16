# This file is sourced into the installer

# Form the Gateway URL
kong_namespace=$(kubectl get svc --all-namespaces -ojsonpath='{.items[?(@.metadata.name=="default-kong")].metadata.namespace}')
kong_port=$(kubectl get svc -n $kong_namespace default-kong -ojsonpath='{.spec.ports[?(@.name=="public-url")].nodePort}')
GESTALT_GATEWAY_URL=$EXTERNAL_GATEWAY_PROTOCOL://$EXTERNAL_GATEWAY_HOST:$kong_port
