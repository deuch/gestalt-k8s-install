exit_with_error() {
  echo "[Error] $@"
  exit 1
}

exit_on_error() {
  if [ $? -ne 0 ]; then
    exit_with_error $1
  fi
}

check_for_required_tools() {
  echo "Checking for required tools..."
  which base64    >/dev/null 2>&1 ; exit_on_error "'base64' not found, aborting."
  which tr        >/dev/null 2>&1 ; exit_on_error "'tr' not found, aborting."
  which helm      >/dev/null 2>&1 ; exit_on_error "'helm' not found, aborting."
  which kubectl   >/dev/null 2>&1 ; exit_on_error "'kubectl' not found, aborting."
  echo "OK - Required tools found."
}

get_kube_context() {
  echo `kubectl config view | grep ^current-context: | awk '{print $2}'`
}

check_for_kube() {
  echo "Checking for Kubernetes..."

  echo "Using Kubernetes context: `get_kube_context`"

  kubectl cluster-info > ./tmp/cluster-info
  exit_on_error "Kubernetes cluster not accessible, aborting."

  echo ""
  cat ./tmp/cluster-info

  echo ""
  echo "OK - Kubernetes cluster is accessible."
}

check_for_helm() {
  echo "Checking for Helm..."
  helm >/dev/null 2>&1
  exit_on_error "'helm' could not be found. Install helm first."

  helm version > /dev/null
  exit_on_error "'helm' doesn't seem to be configured. Try running 'helm version' or 'helm init'"

  echo "OK - Helm is installed."
}

check_for_existing_namespace() {
  echo "Checking for existing Kubernetes namespace '$namespace'..."
  kubectl get namespace $namespace > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo ""
    echo "Kubernetes namespace '$namespace' already exists, aborting.  To delete the namespace, run the following command:"
    echo ""
    echo "  kubectl delete namespace $namespace"
    echo ""
    exit_with_error "Kubernetes namespace '$namespace' already exists, aborting."
  fi
  echo "OK - Kubernetes namespace '$namespace' does not exist."
}

# check_for_existing_namespace_ask() {
#   echo "Checking for existing Kubernetes namespace '$namespace'..."
#   kubectl get namespace $namespace > /dev/null 2>&1
#   if [ $? -eq 0 ]; then
#     while true; do
#         read -p " Kubernetes namespace '$namespace' already exists, proceed? [y/n]: " yn
#         case $yn in
#             [Yy]*) return 0  ;;
#             [Nn]*) echo "Aborted" ; exit  1 ;;
#         esac
#     done
#   fi
#   echo "OK - Kubernetes namespace '$namespace' does not exist."
# }

check_for_prior_install() {
  echo "Checking for prior installation..."

  kubectl get services --all-namespaces | grep default-kong > ./tmp/existing_kong_service
  if [ $? -eq 0 ]; then
    echo ""
    echo "Warning: There are existing namespaces that appear to be from a prior install:"
    cat ./tmp/existing_namespaces
    echo ""
    exit_with_error "'default-kong' service already present"
  fi


  kubectl get namespaces | grep -E '[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}' > ./tmp/existing_namespaces
  if [ $? -eq 0 ]; then
    echo ""
    echo "Warning: There are existing namespaces that appear to be from a prior install:"
    cat ./tmp/existing_namespaces
    echo ""

    if [ -z "$GESTALT_AUTOMATED_INSTALL" ]; then
      do_prompt_to_continue \
        "There appear to be existing namespaces. Recommand inspecting and deleting these namespaces before continuing." \
        "Proceed anyway?"
    else
      echo "Continuing anyway since this is an automated install, press Ctrl-C to cancel..."
      sleep 5
    fi
  else
    echo "OK - No prior installation found."
  fi
}

prompt_to_continue() {
  do_prompt_to_continue \
    "Gestalt Platform is ready to be installed to Kubernetes cluster '`get_kube_context`' in the '$namespace' namespace." \
    "Proceed with Gestalt Platform installation?"
}

do_prompt_to_continue() {
  echo ""
  echo $1
  echo ""

  while true; do
      read -p "$2 [y/n]: " yn
      case $yn in
          [Yy]*) return 0  ;;
          [Nn]*) echo "Aborted" ; exit  1 ;;
      esac
  done
}

process_kubeconfig() {
  echo "Processing kubectl configuration (this gets passed to the installer)..."

  os=`uname`
  outfile=./tmp/kubeconfig.yaml

  if [ -z "$KUBECONFIG_DATA"]; then
    echo "Obtaining kubeconfig from kubectl."

    kubectl config view --raw > ./tmp/kubeconfig
    exit_on_error "Could not process kube config, aborting."

    if [ "$os" == "Darwin" ]; then
      data=`base64 ./tmp/kubeconfig`
    elif [ "$os" == "Linux" ]; then
      data=`base64 ./tmp/kubeconfig | tr -d '\n'`
    else
      echo "Warning: unknown OS type '$os', treating as Linux"
      data=`base64 ./tmp/kubeconfig | tr -d '\n'`
    fi
  else
    echo "kubeconfig data was provided via environment variable."
    data=$KUBECONFIG_DATA
  fi

  cat > $outfile << EOF
# data encoded from $1
kubeconfig: $data
EOF

  echo "Kubernetes config written to $outfile."
}

create_namespace() {
  echo "Checking for existing Kubernetes namespace '$namespace'..."
  kubectl get namespace $namespace > /dev/null 2>&1

  if [ $? -ne 0 ]; then
    echo "Creating namespace '$namespace'..."
    echo ""
    kubectl create namespace $namespace
    exit_on_error "Error creating namespace '$namespace', aborting."

    # Wait for namespace to be created
    sleep 5
    echo "Namespace $namespace created."
  fi
}

run_helm_install() {
  notes=GESTALT_ACCESS_INFO-$GESTALT_DEPLOY_LABEL.txt
  cmd="helm install --namespace $namespace ./gestalt -n gestalt-platform -f ./tmp/kubeconfig.yaml -f $1"

  echo "[Installation initiated at `date`]" >> $notes

  echo "Installing Gestalt Platform to Kubernetes using Helm..." | tee -a $notes
  echo "Command: $cmd"  | tee -a $notes
  $cmd | tee -a $notes
  exit_on_error "Installation failed!"

  echo ""  | tee -a $notes
  echo "Install notes saved to '$notes'."
}

run_post_install() {
  if [ ! -z "$POST_INSTALL_SCRIPT" ]; then
    echo ""
    echo "Running post install script: $POST_INSTALL_SCRIPT ..."
    $POST_INSTALL_SCRIPT
    echo "Done."
  fi
}

prompt_or_wait_to_continue() {
  if [ -z "$GESTALT_AUTOMATED_INSTALL" ]; then
      prompt_to_continue
  else
    echo "About to proceed with installation, press Ctrl-C to cancel..."
    sleep 5
  fi
}