# Validate all ArgoCD applications and configurations
validate: check-tools lint kustomize-build argocd-validate k8s-validate

# Check that required tools are installed
check-tools:
    #!/usr/bin/env bash
    echo "Checking required tools..."
    missing_tools=()
    
    if ! command -v yamllint &> /dev/null; then
        missing_tools+=("yamllint")
    fi
    
    if ! command -v kustomize &> /dev/null; then
        missing_tools+=("kustomize")
    fi
    
    
    if ! command -v kubeconform &> /dev/null; then
        missing_tools+=("kubeconform")
    fi
    
    if ! command -v yq &> /dev/null; then
        missing_tools+=("yq")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo "❌ Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Please install the missing tools using your preferred package manager:"
        echo "  macOS (Homebrew): brew install ${missing_tools[*]}"
        echo "  Ubuntu/Debian:    sudo apt install yamllint && <install others manually>"
        echo ""
        echo "Or install manually from their respective GitHub releases"
        exit 1
    fi
    
    echo "✅ All required tools are installed"

# Lint YAML files for syntax and formatting
lint: check-tools
    yamllint -c .yamllint.yml .

# Validate all Kustomize builds can generate manifests
kustomize-build: check-tools
    #!/usr/bin/env bash
    echo "Validating Kustomize builds..."
    find applications -name "kustomization.yaml" -exec dirname {} \; | \
        while read -r dir; do
            echo "Building: $dir"
            kustomize build "$dir"
        done

# Validate ArgoCD Application manifests (basic YAML structure)
argocd-validate: check-tools
    #!/usr/bin/env bash
    echo "Validating ArgoCD applications..."
    
    # Find files that are specifically ArgoCD Applications
    find . -name "*.yaml" | \
        while read -r file; do
            # Check if this is actually an ArgoCD Application
            api_version=$(yq eval '.apiVersion' "$file" 2>/dev/null)
            kind=$(yq eval '.kind' "$file" 2>/dev/null)
            
            # Skip if not an ArgoCD Application
            if [[ "$api_version" != "argoproj.io/v1alpha1" ]] || [[ "$kind" != "Application" ]]; then
                continue
            fi
            
            echo "Validating: $file"
            
            # Basic validation - check if it's valid YAML and has required ArgoCD fields
            if ! yq eval '.apiVersion' "$file" >/dev/null 2>&1; then
                echo "  ❌ Invalid YAML structure"
                exit 1
            fi
            
            if ! yq eval '.spec.source // .spec.sources' "$file" >/dev/null 2>&1; then
                echo "  ❌ Missing required spec.source or spec.sources"
                exit 1
            fi
            
            if ! yq eval '.spec.destination' "$file" >/dev/null 2>&1; then
                echo "  ❌ Missing required spec.destination"
                exit 1
            fi
            
            echo "  ✅ Valid ArgoCD Application"
        done

# Validate Kubernetes resources against API schemas
k8s-validate: check-tools
    #!/usr/bin/env bash
    echo "Validating Kubernetes resources..."
    find applications -name "kustomization.yaml" -exec dirname {} \; | \
        while read -r dir; do
            echo "Validating resources in: $dir"
            # Build with kustomize and filter out ArgoCD Applications (validated separately)
            # Also add ArgoCD schema support
            kustomize build "$dir" | \
                yq eval 'select(.kind != "Application" or .apiVersion != "argoproj.io/v1alpha1")' - | \
                kubeconform -strict -summary
        done


# Quick syntax check only
quick: check-tools lint kustomize-build

# Clean up any temporary files
clean:
    find . -name "*.tmp" -delete
    find . -name ".kustomize_*" -delete

# List all available recipes
list:
    just --list
