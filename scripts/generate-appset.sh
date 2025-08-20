#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEMPLATE_FILE="generator-template.yaml"
OUTPUT_DIR="applicationset"
CONFIG_FILE="scripts/generator-config.yaml"

print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✅${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}❌${NC} $1"; }

usage() {
    cat << EOF
Usage: $0 [OPTIONS] CHART_NAME NAMESPACE

Generate ArgoCD ApplicationSet from template

Arguments:
  CHART_NAME    Name of the Helm chart
  NAMESPACE     Target namespace for deployment

Options:
  -h, --help              Show this help message
  -t, --template FILE     Template file (default: $TEMPLATE_FILE)
  -o, --output-dir DIR    Output directory (default: $OUTPUT_DIR)
  -c, --config FILE       Configuration file (default: $CONFIG_FILE)
  --external-chart URL    External Helm repository URL
  --chart-version VER     Chart version (for external charts)
  --dry-run              Show output without creating files

Examples:
  # Generate for internal chart
  $0 monitoring-stack monitoring

  # Generate for external chart
  $0 nginx-ingress nginx-system --external-chart https://kubernetes.github.io/ingress-nginx --chart-version 4.10.1

EOF

parse_args() {
    CHART_NAME=""
    NAMESPACE=""
    TEMPLATE_FILE="generator-template.yaml"
    OUTPUT_DIR="applicationset"
    CONFIG_FILE="scripts/generator-config.yaml"
    EXTERNAL_CHART=""
    CHART_VERSION=""
    DRY_RUN=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -t|--template)
                TEMPLATE_FILE="$2"
                shift 2
                ;;
            -o|--output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --external-chart)
                EXTERNAL_CHART="$2"
                shift 2
                ;;
            --chart-version)
                CHART_VERSION="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                if [[ -z "$CHART_NAME" ]]; then
                    CHART_NAME="$1"
                elif [[ -z "$NAMESPACE" ]]; then
                    NAMESPACE="$1"
                else
                    print_error "Too many arguments"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$CHART_NAME" ]] || [[ -z "$NAMESPACE" ]]; then
        print_error "Both CHART_NAME and NAMESPACE are required"
        usage
        exit 1
    fi
}

validate_inputs() {
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        print_error "Template file not found: $TEMPLATE_FILE"
        exit 1
    fi

    if [[ ! -d "$OUTPUT_DIR" ]] && [[ "$DRY_RUN" = false ]]; then
        print_warning "Output directory doesn't exist, creating: $OUTPUT_DIR"
        mkdir -p "$OUTPUT_DIR"
    fi

    # Validate chart name (must be valid Kubernetes resource name)
    if ! [[ "$CHART_NAME" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
        print_error "Invalid chart name. Must be lowercase alphanumeric with hyphens."
        exit 1
    fi

    # Validate namespace name
    if ! [[ "$NAMESPACE" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
        print_error "Invalid namespace. Must be lowercase alphanumeric with hyphens."
        exit 1
    fi
}

generate_content() {
    local content
    content=$(cat "$TEMPLATE_FILE")

    content=${content//CHART_NAME/$CHART_NAME}
    content=${content//NAMESPACE_OF_DEPLOYMENT/$NAMESPACE}

    if [[ -n "$EXTERNAL_CHART" ]]; then
        print_info "Configuring for external chart: $EXTERNAL_CHART"
        
        content=$(echo "$content" | sed '/### Configuração para pegar um helm chart proprio/,/### Configuração para pegar um helm chart externo/d')
        content=${content//https:\/\/kubernetes.github.io\/ingress-nginx/$EXTERNAL_CHART}
        content=${content//ingress-nginx/$CHART_NAME}
        
        if [[ -n "$CHART_VERSION" ]]; then
            content=${content//\"4.10.1\"/\"$CHART_VERSION\"}
        fi
    else
        print_info "Configuring for internal chart"
        
        content=$(echo "$content" | sed '/### Configuração para pegar um helm chart externo/,$d')
    fi

    echo "$content"
}

main() {
    parse_args "$@"
    validate_inputs

    print_info "Generating ApplicationSet for chart: $CHART_NAME"
    print_info "Target namespace: $NAMESPACE"

    local output_file="$OUTPUT_DIR/$CHART_NAME.yaml"
    local content
    content=$(generate_content)

    if [[ "$DRY_RUN" = true ]]; then
        print_info "Dry run - ApplicationSet content:"
        echo "---"
        echo "$content"
        echo "---"
    else
        echo "$content" > "$output_file"
        print_success "ApplicationSet generated: $output_file"
        
        if command -v yq >/dev/null 2>&1; then
            if yq eval '.' "$output_file" >/dev/null 2>&1; then
                print_success "YAML syntax is valid"
            else
                print_error "Generated YAML has syntax errors"
                exit 1
            fi
        elif command -v yamllint >/dev/null 2>&1; then
            if yamllint "$output_file" >/dev/null 2>&1; then
                print_success "YAML syntax is valid"
            else
                print_warning "YAML validation failed (install yq for better validation)"
            fi
        else
            print_warning "No YAML validator found (install yq or yamllint for validation)"
        fi
    fi

    print_success "Generation complete!"
}

main "$@"