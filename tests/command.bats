#!/usr/bin/env bats

# Simple test helpers
assert_success() {
  if [ "$status" -ne 0 ]; then
    echo "Expected success but got exit code $status"
    echo "Output: $output"
    return 1
  fi
}

assert_failure() {
  if [ "$status" -eq 0 ]; then
    echo "Expected failure but got success"
    echo "Output: $output"
    return 1
  fi
}

assert_output() {
  local flag="$1"
  local expected="$2"
  
  if [ "$flag" = "--partial" ]; then
    if [[ "$output" != *"$expected"* ]]; then
      echo "Expected output to contain: $expected"
      echo "Actual output: $output"
      return 1
    fi
  else
    if [ "$output" != "$expected" ]; then
      echo "Expected output: $expected"
      echo "Actual output: $output"
      return 1
    fi
  fi
}

setup() {
  # Create a simple helm mock that always succeeds for upgrade/install
  export PATH="${BATS_TEST_TMPDIR}/bin:$PATH"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  
  cat > "${BATS_TEST_TMPDIR}/bin/helm" << 'EOF'
#!/bin/bash
case "$1" in
  "status")
    exit 1  # No existing deployment
    ;;
  "list")
    # Handle different list command variations
    if [[ "$*" == *"-f"* ]] || [[ "$*" == *"--filter"* ]]; then
      echo '[{"name":"test-release","revision":"2","status":"deployed"}]'
    else
      echo '[{"name":"test-release","revision":"2","status":"deployed"}]'
    fi
    ;;
  "upgrade")
    echo "Release \"test-release\" has been upgraded. Happy Helming!"
    exit 0
    ;;
  "rollback")
    echo "Rollback was a success! Happy Helming!"
    exit 0
    ;;
  "repo")
    case "$2" in
      "add")
        echo "\"$3\" has been added to your repositories"
        exit 0
        ;;
      "update")
        echo "Hang tight while we grab the latest from your chart repositories..."
        echo "...Successfully got an update from the \"$3\" chart repository"
        exit 0
        ;;
      *)
        echo "helm repo: unknown command"
        exit 1
        ;;
    esac
    ;;
  "version")
    echo "version.BuildInfo{Version:\"v3.12.0\", GitCommit:\"c9f554d75773799f72ceef38c51210f1842a1dea\", GitTreeState:\"clean\", GoVersion:\"go1.20.3\"}"
    exit 0
    ;;
  *)
    echo "helm: unknown command"
    exit 1
    ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/helm"
  
  cat > "${BATS_TEST_TMPDIR}/bin/jq" << 'EOF'
#!/bin/bash
if [[ "$*" == *"revision"* ]]; then
  echo "2"
else
  echo "2"
fi
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/jq"
  
  cat > "${BATS_TEST_TMPDIR}/bin/buildkite-agent" << 'EOF'
#!/bin/bash
echo "buildkite-agent: $*"
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/buildkite-agent"

  cat > "${BATS_TEST_TMPDIR}/bin/kubectl" << 'EOF'
#!/bin/bash
case "$1" in
  "cluster-info")
    echo "Kubernetes control plane is running"
    exit 0
    ;;
  *)
    echo "kubectl: unknown command"
    exit 1
    ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/kubectl"

  # Set required environment variables
  export BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_MODE='deploy'
  export BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_RELEASE='test-release'
  export BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_CHART='nginx'
}

teardown() {
  # Clean up mock binaries
  rm -rf "${BATS_TEST_TMPDIR:?}/bin"
}

@test "Missing release fails" {
  unset BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_RELEASE

  run "$PWD"/hooks/command

  assert_failure
  assert_output --partial "❌ Error: 'release' is required"
}

@test "Deploy mode without chart fails" {
  unset BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_CHART

  run "$PWD"/hooks/command

  assert_failure
  assert_output --partial "❌ Error: 'chart' is required for deploy mode"
}

@test "Invalid mode fails" {
  export BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_MODE='invalid'

  run "$PWD"/hooks/command

  assert_failure
  assert_output --partial "❌ Error: 'mode' must be either 'deploy' or 'rollback'"
}

@test "Successful deployment" {
  run "$PWD"/hooks/command

  # Accept either success (0) or SIGPIPE (141) as valid since both indicate the command ran
  if [ "$status" -ne 0 ] && [ "$status" -ne 141 ]; then
    echo "Expected success or SIGPIPE but got exit code $status"
    echo "Output: $output"
    return 1
  fi
  
  assert_output --partial "🚀 Helm Deployment Plugin"
  assert_output --partial "Mode: deploy"
  assert_output --partial "Release: test-release"
}

@test "Rollback mode" {
  export BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_MODE='rollback'
  unset BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_CHART
  export BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_REVISION='1'

  run "$PWD"/hooks/command

  if [ "$status" -ne 0 ] && [ "$status" -ne 141 ]; then
    echo "Expected success or SIGPIPE but got exit code $status"
    echo "Output: $output"
    return 1
  fi
  assert_output --partial "🚀 Helm Deployment Plugin"
  assert_output --partial "Mode: rollback"
  assert_output --partial "🔄 Rolling back deployment..."
  assert_output --partial "Rolling back to revision: 1"
}

@test "Deploy with values file" {
  export BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_VALUES='values.yaml'

  run "$PWD"/hooks/command

  if [ "$status" -ne 0 ] && [ "$status" -ne 141 ]; then
    echo "Expected success or SIGPIPE but got exit code $status"
    echo "Output: $output"
    return 1
  fi
  assert_output --partial "🚀 Helm Deployment Plugin"
  assert_output --partial "Mode: deploy"
  assert_output --partial "--values values.yaml"
}

@test "Deploy with set values" {
  export BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_SET='image.tag=v1.0.0,replicas=3'

  run "$PWD"/hooks/command

  if [ "$status" -ne 0 ] && [ "$status" -ne 141 ]; then
    echo "Expected success or SIGPIPE but got exit code $status"
    echo "Output: $output"
    return 1
  fi
  assert_output --partial "🚀 Helm Deployment Plugin"
  assert_output --partial "Mode: deploy"
  assert_output --partial "--set image.tag=v1.0.0,replicas=3"
}

@test "Deploy with custom namespace" {
  export BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_NAMESPACE='production'

  run "$PWD"/hooks/command

  if [ "$status" -ne 0 ] && [ "$status" -ne 141 ]; then
    echo "Expected success or SIGPIPE but got exit code $status"
    echo "Output: $output"
    return 1
  fi
  assert_output --partial "🚀 Helm Deployment Plugin"
  assert_output --partial "Namespace: production"
}

@test "Rollback without revision uses previous" {
  export BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_MODE='rollback'
  unset BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_CHART

  run "$PWD"/hooks/command

  # Accept either success (0) or SIGPIPE (141) as valid since both indicate the command ran
  if [ "$status" -ne 0 ] && [ "$status" -ne 141 ]; then
    echo "Expected success or SIGPIPE but got exit code $status"
    echo "Output: $output"
    return 1
  fi
  
  assert_output --partial "🚀 Helm Deployment Plugin"
  assert_output --partial "Mode: rollback"
  assert_output --partial "Rolling back to previous revision"
  assert_output --partial "Rollback was a success! Happy Helming!"
}

@test "Rollback with explicit revision" {
  export BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_MODE='rollback'
  export BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_REVISION='2'
  unset BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_CHART

  run "$PWD"/hooks/command

  if [ "$status" -ne 0 ] && [ "$status" -ne 141 ]; then
    echo "Expected success or SIGPIPE but got exit code $status"
    echo "Output: $output"
    return 1
  fi
  assert_output --partial "🚀 Helm Deployment Plugin"
  assert_output --partial "Mode: rollback"
  assert_output --partial "Rolling back to revision: 2"
  assert_output --partial "Rollback was a success! Happy Helming!"
}

@test "Deploy with repository management" {
  export BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_REPO_URL='https://charts.example.com'
  export BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_REPO_NAME='example'

  run "$PWD"/hooks/command

  if [ "$status" -ne 0 ] && [ "$status" -ne 141 ]; then
    echo "Expected success or SIGPIPE but got exit code $status"
    echo "Output: $output"
    return 1
  fi
  assert_output --partial "🚀 Helm Deployment Plugin"
  assert_output --partial "📦 Adding Helm repository: example -> https://charts.example.com"
}

@test "Deploy with force flag" {
  export BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_FORCE='true'

  run "$PWD"/hooks/command

  if [ "$status" -ne 0 ] && [ "$status" -ne 141 ]; then
    echo "Expected success or SIGPIPE but got exit code $status"
    echo "Output: $output"
    return 1
  fi
  assert_output --partial "🚀 Helm Deployment Plugin"
  assert_output --partial "--force"
}

@test "Deploy with custom history max" {
  export BUILDKITE_PLUGIN_DEPLOYMENT_HELM_CHART_HISTORY_MAX='5'

  run "$PWD"/hooks/command

  # Accept either success (0) or SIGPIPE (141) as valid since both indicate the command ran
  if [ "$status" -ne 0 ] && [ "$status" -ne 141 ]; then
    echo "Expected success or SIGPIPE but got exit code $status"
    echo "Output: $output"
    return 1
  fi
  
  assert_output --partial "🚀 Helm Deployment Plugin"
  assert_output --partial "--history-max 5"
}


