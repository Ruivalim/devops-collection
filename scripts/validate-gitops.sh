#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✅${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}❌${NC} $1"; }

ERRORS=0
WARNINGS=0

error() {
    print_error "$1"
    ((ERRORS++))
}

warning() {
    print_warning "$1"
    ((WARNINGS++))
}

check_dependencies() {
    print_info "Checking dependencies..."
    
    local deps=("helm" "kubectl")
    local optional_deps=("yq" "yamllint")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            error "Required dependency missing: $dep"
        fi
    done
    
    for dep in "${optional_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            warning "Optional dependency missing: $dep (recommended for better validation)"
        fi
    done
}

validate_yaml_syntax() {
    local file="$1"
    
    if command -v yq >/dev/null 2>&1; then
        if ! yq eval '.' "$file" >/dev/null 2>&1; then
            error "Invalid YAML syntax in $file"
            return 1
        fi
    elif command -v yamllint >/dev/null 2>&1; then
        if ! yamllint "$file" >/dev/null 2>&1; then
            error "YAML validation failed for $file"
            return 1
        fi
    else
        warning "No YAML validator available for $file"
    fi
    return 0
}

# Validate ApplicationSet files
validate_applicationsets() {
    print_info "Validating ApplicationSets..."
    
    if [[ ! -d "applicationset" ]]; then
        warning "No applicationset directory found"
        return
    fi
    
    local count=0
    while IFS= read -r -d '' file; do
        print_info "Validating ApplicationSet: $(basename "$file")"
        
        if validate_yaml_syntax "$file"; then
            local kind
            kind=$(yq eval '.kind // "unknown"' "$file" 2>/dev/null || echo "unknown")
            
            if [[ "$kind" != "ApplicationSet" ]]; then
                error "File $file is not an ApplicationSet (kind: $kind)"
            fi
            
            if grep -q "CHART_NAME\|NAMESPACE_OF_DEPLOYMENT" "$file"; then
                error "Unreplaced placeholders found in $file"
            fi
            
            if grep -q "your-cluster.region.cloudprovider.com" "$file"; then
                warning "Generic cluster URLs found in $file - update with real cluster endpoints"
            fi
        fi
        
        ((count++))
    done < <(find applicationset -name "*.yaml" -o -name "*.yml" -print0 2>/dev/null || true)
    
    if [[ $count -eq 0 ]]; then
        warning "No ApplicationSet files found"
    else
        print_success "Validated $count ApplicationSet files"
    fi
}

validate_helm_charts() {
    print_info "Validating Helm charts..."
    
    if [[ ! -d "charts" ]]; then
        warning "No charts directory found"
        return
    fi
    
    local count=0
    while IFS= read -r -d '' chart_dir; do
        local chart_name
        chart_name=$(basename "$chart_dir")
        print_info "Validating Helm chart: $chart_name"
        
        if [[ ! -f "$chart_dir/Chart.yaml" ]]; then
            error "Missing Chart.yaml in $chart_name"
            continue
        fi
        
        if [[ ! -f "$chart_dir/values.yaml" ]]; then
            warning "Missing values.yaml in $chart_name"
        fi
        
        if [[ ! -d "$chart_dir/templates" ]]; then
            error "Missing templates directory in $chart_name"
            continue
        fi
        
        if command -v helm >/dev/null 2>&1; then
            if ! helm lint "$chart_dir" >/dev/null 2>&1; then
                error "Helm lint failed for $chart_name"
            fi
        fi
        
        ((count++))
    done < <(find charts -maxdepth 1 -type d ! -path charts -print0 2>/dev/null || true)
    
    if [[ $count -eq 0 ]]; then
        warning "No Helm charts found"
    else
        print_success "Validated $count Helm charts"
    fi
}

validate_overlays() {
    print_info "Validating overlay structure..."
    
    if [[ ! -d "overlays" ]]; then
        warning "No overlays directory found"
        return
    fi
    
    local environments
    environments=$(find overlays -maxdepth 1 -type d ! -path overlays -exec basename {} \; 2>/dev/null || true)
    
    if [[ -z "$environments" ]]; then
        warning "No environments found in overlays"
        return
    fi
    
    print_info "Found environments: $environments"
    
    for env in $environments; do
        print_info "Validating environment: $env"
        
        local charts
        charts=$(find "overlays/$env" -maxdepth 1 -type d ! -path "overlays/$env" -exec basename {} \; 2>/dev/null || true)
        
        for chart in $charts; do
            local values_file="overlays/$env/$chart/values.yaml"
            if [[ -f "$values_file" ]]; then
                validate_yaml_syntax "$values_file" || true
            else
                warning "Missing values.yaml for $chart in $env environment"
            fi
        done
    done
}

check_security() {
    print_info "Checking for security issues..."
    
    local secret_patterns=("password" "secret" "key" "token" "credential")
    
    for pattern in "${secret_patterns[@]}"; do
        if grep -r -i "$pattern.*:" . --include="*.yaml" --include="*.yml" >/dev/null 2>&1; then
            warning "Found potential secrets in YAML files (pattern: $pattern)"
        fi
    done
    
    if grep -r -E "(admin|password|secret).*:.*['\"]?(admin|password|123|default)" . --include="*.yaml" --include="*.yml" >/dev/null 2>&1; then
        error "Found default passwords in configuration files"
    fi
}

main() {
    print_info "Starting GitOps validation..."
    
    check_dependencies
    validate_applicationsets
    validate_helm_charts
    validate_overlays
    check_security
    
    print_info "Validation complete!"
    
    if [[ $ERRORS -gt 0 ]]; then
        print_error "Found $ERRORS errors and $WARNINGS warnings"
        exit 1
    elif [[ $WARNINGS -gt 0 ]]; then
        print_warning "Found $WARNINGS warnings (no errors)"
        exit 0
    else
        print_success "No issues found!"
        exit 0
    fi
}

main "$@"