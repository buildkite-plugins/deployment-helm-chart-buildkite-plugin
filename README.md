# Deployment Helm Chart Buildkite Plugin

Buildkite plugin for Helm chart deployments and rollbacks

## Options

These are all the options available to configure this plugin's behaviour.

### Required

#### `mode` (string)

Operation mode for the plugin.

- `deploy`: Deploy or upgrade a Helm chart
- `rollback`: Rollback a deployment to a previous revision

#### `release` (string)

The Helm release name.

#### `chart` (string, required for deploy mode)

Helm chart name or path. Can be:

- Chart name from a repository (e.g., `nginx`)
- Local chart path (e.g., `./charts/my-app`)
- Chart with repository (e.g., `bitnami/nginx`)

### Optional

#### `namespace` (string)

Kubernetes namespace for the deployment. Defaults to `default`.

#### `values` (array)

Array of values files to use with Helm.

#### `set` (array)

Array of key=value pairs to set via `--set`.

#### `kubeconfig` (string)

Path to kubeconfig file. If not specified, uses the default kubeconfig.

#### `timeout` (string)

Timeout for Helm operations. Defaults to `300s`.

#### `wait` (boolean)

Wait for deployment to complete. Defaults to `true`.

#### `atomic` (boolean)

If set, upgrade process rolls back changes made in case of failed upgrade. Defaults to `true`.

#### `create_namespace` (boolean)

Create namespace if it doesn't exist. Defaults to `false`.

#### `dry_run` (boolean)

Simulate deployment without making changes. Defaults to `false`.

#### `revision` (number)

Specific revision to rollback to (for rollback mode). If not specified, rolls back to the previous revision.

#### `repo_url` (string)

Helm repository URL to add before deployment. Must be used together with `repo_name`.

#### `repo_name` (string)

Name for the Helm repository. Must be used together with `repo_url`.

#### `force` (boolean)

Force resource updates through a replacement strategy. Defaults to `false`.

#### `history_max` (number)

Maximum number of revisions saved per release. Defaults to `10`.

## Examples

### Basic Deployment

```yaml
steps:
  - label: "🚀 Deploy Application"
    plugins:
      - deployment-helm-chart#v1.0.0:
          mode: deploy
          chart: nginx
          release: my-app
          namespace: production
```

### Advanced Deployment with Values

```yaml
steps:
  - label: "🚀 Deploy with Custom Values"
    plugins:
      - deployment-helm-chart#v1.0.0:
          mode: deploy
          chart: ./charts/my-app
          release: my-app
          namespace: production
          values:
            - values/production.yaml
            - values/secrets.yaml
          set:
            - image.tag=${BUILDKITE_COMMIT}
            - replicas=3
          timeout: 600s
          wait: true
          atomic: true
          force: false
          history_max: 15
```

### Deployment with Custom Repository

```yaml
steps:
  - label: "🚀 Deploy from Custom Repository"
    plugins:
      - deployment-helm-chart#v1.0.0:
          mode: deploy
          chart: mycompany/webapp
          release: my-app
          namespace: production
          repo_url: https://charts.mycompany.com
          repo_name: mycompany
          force: true
          history_max: 5
```

### Rollback Deployment

```yaml
steps:
  - label: "🔄 Rollback Deployment"
    plugins:
      - deployment-helm-chart#v1.0.0:
          mode: rollback
          release: my-app
          namespace: production
          revision: 5  # Optional: specific revision to rollback to
```

### Complete Workflow with Block Step

```yaml
steps:
  - label: "🚀 Deploy Application"
    key: "deploy"
    plugins:
      - deployment-helm-chart#v1.0.0:
          mode: deploy
          chart: nginx
          release: my-app
          namespace: production

  - block: "🤔 Rollback deployment?"
    key: "rollback-gate"
    depends_on: "deploy"
    blocked_state: "passed"

  - label: "🔄 Rollback Deployment"
    depends_on: "rollback-gate"
    plugins:
      - deployment-helm-chart#v1.0.0:
          mode: rollback
          release: my-app
          namespace: production
```

## Compatibility

| Elastic Stack | Agent Stack K8s | Hosted (Mac) | Hosted (Linux) | Notes |
| :-----------: | :-------------: | :----: | :----: |:---- |
| ✅ | ✅ | ✅ | ✅ | Tested with AWS EKS |

- ✅ Fully supported (all combinations of attributes have been tested to pass)
- ⚠️ Partially supported (some combinations cause errors/issues)
- ❌ Not supported

## RBAC Requirements

Your Kubernetes service account needs the following permissions in target namespaces:

### Required Permissions

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: helm-deployer
  namespace: <target-namespace>
rules:
- apiGroups: [""]
  resources: ["secrets", "configmaps", "services", "pods"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "daemonsets", "statefulsets"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
```

### For Cross-Namespace Deployments

Use `ClusterRole` instead of `Role` for cluster-wide permissions.

### Troubleshooting RBAC Issues

```bash
# Test if your service account has required permissions
kubectl auth can-i create deployments --as=system:serviceaccount:namespace:sa-name -n target-namespace
kubectl auth can-i get secrets --as=system:serviceaccount:namespace:sa-name -n target-namespace
```

If you see permission errors, verify your service account has the required permissions listed above.

## 👩‍💻 Contributing

1. Fork the repo
2. Make the changes
3. Run the tests
4. Commit and push your changes
5. Send a pull request

## Developing

To run testing, shellchecks, and plugin linting, use `bk run` with the [Buildkite CLI](https://github.com/buildkite/cli):

```bash
bk run
```

Alternatively, to run just the tests, you can use the [Buildkite Plugin Tester](https://github.com/buildkite-plugins/buildkite-plugin-tester):

```bash
docker run --rm -ti -v "${PWD}":/plugin buildkite/plugin-tester:latest
```

## 📜 License

The package is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
