#!/usr/bin/env sh

set -eu

REQUIRED_COMMANDS="helm tar"
REQUIRED_ENV_VARS="HELM_REPO_NAME HELM_REPO_URL HELM_REPO_USERNAME HELM_REPO_PASSWORD"
ENV_FILE="${ENV_FILE:-.env}"
CHART_DIR="${CHART_DIR:-.}"
DEBUG=0
QUIET=0
START_TIME="$(date +%s)"
CURRENT_STEP=""
TEMP_FILES=""
OUTPUT_OVERWRITE_CONFIRMED=0

print_banner() {
  [ "$QUIET" -eq 0 ] || return 0
  echo "======================================================"
  echo " Ressuite Helm Bootstrap"
  echo "======================================================"
}

log_info() {
  [ "$QUIET" -eq 0 ] || return 0
  printf 'INFO  %s\n' "$1"
}

log_ok() {
  [ "$QUIET" -eq 0 ] || return 0
  printf 'OK    %s\n' "$1"
}

log_warn() {
  [ "$QUIET" -eq 0 ] || return 0
  printf 'WARN  %s\n' "$1"
}

log_error() {
  printf 'ERROR %s\n' "$1" >&2
}

log_debug() {
  [ "$DEBUG" -eq 1 ] || return 0
  printf '      %s\n' "$1"
}

log_detail() {
  [ "$DEBUG" -eq 1 ] || return 0
  log_debug "$1"
}

section() {
  [ "$QUIET" -eq 0 ] || return 0
  echo ""
  echo "$1"
}

print_context() {
  [ "$QUIET" -eq 0 ] || return 0

  section "Contesto"
  key_value "Workdir" "$(pwd)"
  key_value "Env file" "$ENV_FILE"
  key_value "Chart dir" "$CHART_DIR"
  key_value "Helm repo" "$HELM_REPO_NAME"
  key_value "Repo URL" "$HELM_REPO_URL"
  key_value "Auth user" "$HELM_REPO_USERNAME"
  key_value "Log mode" "$(log_mode)"
}

log_mode() {
  if [ "$DEBUG" -eq 1 ]; then
    printf 'debug'
  elif [ "$QUIET" -eq 1 ]; then
    printf 'quiet'
  else
    printf 'normal'
  fi
}

usage() {
  cat <<'EOF'
Uso: ./ressuite-helm-bootstrap.sh [opzioni]

Opzioni:
  --debug      Mostra log dettagliati
  --quiet      Mostra solo gli errori
  -h, --help   Mostra questo aiuto

Variabili:
  ENV_FILE              Percorso del file env da caricare, default .env
  CHART_DIR             Cartella del chart Helm, default .
                        Da qui vengono letti Chart.yaml, charts/, config e values-template.yaml.
  HELM_REPO_NAME        Nome locale del repository Helm
  HELM_REPO_URL         URL del repository Helm
  HELM_REPO_USERNAME    Username del repository Helm
  HELM_REPO_PASSWORD    Password/token del repository Helm
EOF
}

die() {
  log_error "$*"
  exit 1
}

key_value() {
  [ "$QUIET" -eq 0 ] || return 0
  printf '  %-12s : %s\n' "$1" "$2"
}

elapsed_since() {
  start="$1"
  now="$(date +%s)"
  printf '%ss' "$((now - start))"
}

format_command_for_log() {
  masked_command=""
  mask_next=0

  for arg in "$@"; do
    if [ "$mask_next" -eq 1 ]; then
      arg="******"
      mask_next=0
    else
      case "$arg" in
        --password)
          mask_next=1
          ;;
        --password=*)
          arg="--password=******"
          ;;
        "$HELM_REPO_PASSWORD")
          arg="******"
          ;;
      esac
    fi

    masked_command="${masked_command} ${arg}"
  done

  printf '%s' "${masked_command# }"
}

finish() {
  status="$?"

  cleanup_temp_files

  if [ "$status" -eq 0 ]; then
    [ "$QUIET" -eq 1 ] || printf '\n'
    log_ok "Completato in $(elapsed_since "$START_TIME")"
    return 0
  fi

  if [ -n "$CURRENT_STEP" ]; then
    log_error "Fase fallita: $CURRENT_STEP"
  fi
  log_error "Interrotto dopo $(elapsed_since "$START_TIME")"
  exit "$status"
}

register_temp_file() {
  TEMP_FILES="${TEMP_FILES}
$1"
}

register_temp_dir() {
  TEMP_FILES="${TEMP_FILES}
$1"
}

cleanup_temp_files() {
  for temp_path in $TEMP_FILES; do
    [ -n "$temp_path" ] || continue
    if [ -d "$temp_path" ]; then
      rm -rf "$temp_path"
    elif [ -e "$temp_path" ]; then
      rm -f "$temp_path"
    fi
  done
}

run_step() {
  CURRENT_STEP="$1"
  shift

  step_start="$(date +%s)"
  output_file=""

  log_info "$CURRENT_STEP"
  log_detail "Comando: $(format_command_for_log "$@")"

  if [ "$DEBUG" -eq 1 ]; then
    "$@"
  else
    output_file="$(mktemp)"
    register_temp_file "$output_file"
    if ! "$@" >"$output_file" 2>&1; then
      if [ -s "$output_file" ]; then
        log_error "Comando fallito. Riesegui con --debug per vedere l'output completo."
      fi
      return 1
    fi
  fi

  log_ok "$CURRENT_STEP ($(elapsed_since "$step_start"))"
  CURRENT_STEP=""
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --debug)
        DEBUG=1
        ;;
      --quiet)
        QUIET=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "opzione non riconosciuta: $1"
        ;;
    esac
    shift
  done
}

load_env_file() {
  env_path=""
  sanitized_env_file=""
  cr="$(printf '\r')"

  if [ ! -f "$ENV_FILE" ]; then
    log_detail "File env non trovato: $ENV_FILE"
    return 0
  fi

  log_info "Carico il file ambiente: $ENV_FILE"
  case "$ENV_FILE" in
    */*|./*|../*)
      env_path="$ENV_FILE"
      ;;
    *)
      env_path="./$ENV_FILE"
      ;;
  esac

  sanitized_env_file="$(mktemp)"
  register_temp_file "$sanitized_env_file"
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$cr}"
    printf '%s\n' "$line"
  done < "$env_path" > "$sanitized_env_file"

  set -a
  # shellcheck disable=SC1090
  . "$sanitized_env_file"
  set +a
  log_ok "File ambiente caricato"
}

missing_env_vars() {
  missing=""

  for var_name in $REQUIRED_ENV_VARS; do
    eval "value=\${$var_name:-}"
    if [ -z "$value" ]; then
      missing="${missing} ${var_name}"
    fi
  done

  printf '%s' "$missing"
}

check_commands() {
  missing=""

  section "Preflight"
  log_info "Verifico i comandi richiesti"
  for command_name in $REQUIRED_COMMANDS; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing="${missing} ${command_name}"
      log_detail "Comando mancante: $command_name"
    else
      log_detail "Comando trovato: $command_name"
    fi
  done

  [ -z "$missing" ] || die "comandi mancanti:${missing}"
  log_ok "Comandi richiesti disponibili"
}

check_env() {
  log_info "Verifico le variabili ambiente richieste"
  missing="$(missing_env_vars)"

  if [ -n "$missing" ]; then
    log_detail "Variabili mancanti prima del caricamento:${missing}"
    load_env_file
    missing="$(missing_env_vars)"
  fi

  [ -z "$missing" ] || die "Variabili ambiente mancanti:${missing}"
  log_ok "Variabili ambiente disponibili"
}

add_helm_repo() {
  log_detail "Repo URL: $HELM_REPO_URL"
  run_step "Configuro il repository Helm '$HELM_REPO_NAME'" \
    helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL" \
    --username "$HELM_REPO_USERNAME" \
    --password "$HELM_REPO_PASSWORD" \
    --force-update
}

update_dependencies() {
  run_step "Aggiorno le dipendenze Helm in '$CHART_DIR'" \
    helm dependency update "$CHART_DIR"
}

strip_yaml_value() {
  value="$1"
  cr="$(printf '\r')"
  value="${value%%#*}"

  while :; do
    case "$value" in
      " "*) value="${value# }" ;;
      "	"*) value="${value#	}" ;;
      *) break ;;
    esac
  done

  while :; do
    case "$value" in
      *" ") value="${value% }" ;;
      *"	") value="${value%	}" ;;
      *"$cr") value="${value%$cr}" ;;
      *) break ;;
    esac
  done

  case "$value" in
    \"*\") value="${value#\"}"; value="${value%\"}" ;;
    \'*\') value="${value#\'}"; value="${value%\'}" ;;
  esac

  printf '%s' "$value"
}

extract_yaml_field_value() {
  line="$1"
  key="$2"
  value="${line#*${key}:}"
  strip_yaml_value "$value"
}

resolve_ressuite_dependency_version() {
  chart_file="$CHART_DIR/Chart.yaml"
  in_dependencies=0
  in_dependency=0
  dependency_name=""
  dependency_version=""
  found_count=0
  found_version=""

  [ -f "$chart_file" ] || die "Chart.yaml non trovato: $chart_file"

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      dependencies:*)
        in_dependencies=1
        continue
        ;;
    esac

    if [ "$in_dependencies" -eq 0 ]; then
      continue
    fi

    case "$line" in
      [![:space:]]*)
        break
        ;;
    esac

    case "$line" in
      *-*"name:"*)
        if [ "$in_dependency" -eq 1 ] && [ "$dependency_name" = "ressuite" ]; then
          found_count=$((found_count + 1))
          found_version="$dependency_version"
        fi
        in_dependency=1
        dependency_name="$(extract_yaml_field_value "$line" "name")"
        dependency_version=""
        ;;
      *"name:"*)
        [ "$in_dependency" -eq 1 ] || continue
        dependency_name="$(extract_yaml_field_value "$line" "name")"
        ;;
      *"version:"*)
        [ "$in_dependency" -eq 1 ] || continue
        dependency_version="$(extract_yaml_field_value "$line" "version")"
        ;;
    esac
  done < "$chart_file"

  if [ "$in_dependency" -eq 1 ] && [ "$dependency_name" = "ressuite" ]; then
    found_count=$((found_count + 1))
    found_version="$dependency_version"
  fi

  if [ "$found_count" -eq 0 ]; then
    die "Dipendenza 'ressuite' non trovata in $chart_file"
  fi
  if [ "$found_count" -gt 1 ]; then
    die "Trovate più dipendenze con name 'ressuite' in $chart_file"
  fi
  if [ -z "$found_version" ]; then
    die "Versione mancante per la dipendenza 'ressuite' in $chart_file"
  fi

  printf '%s' "$found_version"
}

confirm_overwrite() {
  target_path="$1"
  answer=""

  if [ ! -e "$target_path" ]; then
    return 0
  fi

  if [ "$QUIET" -eq 1 ]; then
    die "Esiste già: $target_path. Rilancia senza --quiet per confermare la sovrascrittura."
  fi

  printf 'WARN  %s esiste già. Sovrascrivere? [y/N] ' "$target_path"
  read -r answer
  [ "$QUIET" -eq 1 ] || echo ""

  case "$answer" in
    y|Y|yes|YES|Yes|s|S|si|SI|Si)
      return 0
      ;;
    *)
      die "Operazione annullata: sovrascrittura negata per $target_path"
      ;;
  esac
}

existing_output_paths() {
  existing=""

  for output_path in "$CHART_DIR/config" "$CHART_DIR/values-template.yaml" "$CHART_DIR/charts"; do
    if [ -e "$output_path" ]; then
      existing="${existing}
$output_path"
    fi
  done

  printf '%s' "$existing"
}

confirm_output_cleanup() {
  existing_paths="$(existing_output_paths)"
  answer=""

  section "Output"

  if [ -z "$existing_paths" ]; then
    log_info "Nessun output esistente da rimuovere"
    OUTPUT_OVERWRITE_CONFIRMED=1
    return 0
  fi

  if [ "$QUIET" -eq 1 ]; then
    die "Output esistenti da rimuovere. Rilancia senza --quiet per confermare l'eliminazione."
  fi

  log_warn "Verranno eliminati questi output esistenti:"
  for output_path in $existing_paths; do
    log_warn "  $output_path"
  done

  printf 'WARN  Procedere con eliminazione e rigenerazione? [y/N] '
  read -r answer
  echo ""

  case "$answer" in
    y|Y|yes|YES|Yes|s|S|si|SI|Si)
      ;;
    *)
      die "Operazione annullata: eliminazione output negata"
      ;;
  esac

  OUTPUT_OVERWRITE_CONFIRMED=1
}

delete_existing_outputs() {
  for output_path in "$CHART_DIR/config" "$CHART_DIR/values-template.yaml" "$CHART_DIR/charts"; do
    if [ -e "$output_path" ]; then
      rm -rf "$output_path"
      log_ok "Rimosso $output_path"
    fi
  done
}

cleanup_helm_artifacts() {
  for output_path in "$CHART_DIR/Chart.lock"; do
    if [ -e "$output_path" ]; then
      rm -rf "$output_path"
      log_ok "Rimosso $output_path"
    fi
  done
}

copy_chart_artifact() {
  source_path="$1"
  target_path="$2"
  label="$3"

  if [ ! -e "$source_path" ]; then
    log_detail "$label non presente nel chart estratto"
    return 0
  fi

  [ "$OUTPUT_OVERWRITE_CONFIRMED" -eq 1 ] || confirm_overwrite "$target_path"

  cp -R "$source_path" "$target_path"
  log_ok "$label -> $target_path"
}

copy_values_yaml() {
  source_path="$1"
  target_path="$2"
  temp_file=""

  if [ ! -e "$source_path" ]; then
    log_detail "values.yaml non presente nel chart estratto"
    return 0
  fi

  [ "$OUTPUT_OVERWRITE_CONFIRMED" -eq 1 ] || confirm_overwrite "$target_path"

  temp_file="$(mktemp)"
  register_temp_file "$temp_file"

  printf 'ressuite:\n' > "$temp_file"
  while IFS= read -r line || [ -n "$line" ]; do
    printf '  %s\n' "$line" >> "$temp_file"
  done < "$source_path"

  mv "$temp_file" "$target_path"
  log_ok "values-template.yaml -> $target_path"
}

import_ressuite_defaults() {
  version="$(resolve_ressuite_dependency_version)"
  package_file="$CHART_DIR/charts/ressuite-${version}.tgz"
  extract_dir="$(mktemp -d)"
  extracted_chart_dir="$extract_dir/ressuite"

  register_temp_dir "$extract_dir"

  log_detail "Dipendenza ressuite letta da $CHART_DIR/Chart.yaml: versione $version"
  log_detail "Pacchetto atteso: $package_file"

  [ -f "$package_file" ] || die "Pacchetto Helm non trovato: $package_file"

  run_step "Scompatto il chart ressuite $version" \
    tar -xzf "$package_file" -C "$extract_dir"

  [ -d "$extracted_chart_dir" ] || die "Directory 'ressuite' non trovata nel pacchetto $package_file"
  log_detail "Chart estratto in: $extracted_chart_dir"

  copy_chart_artifact "$extracted_chart_dir/files" "$CHART_DIR/config" "Cartella config"
  copy_values_yaml "$extracted_chart_dir/values.yaml" "$CHART_DIR/values-template.yaml"
}

main() {
  parse_args "$@"
  trap finish EXIT
  print_banner
  check_commands
  check_env
  confirm_output_cleanup
  delete_existing_outputs
  print_context
  section "Helm"
  add_helm_repo
  update_dependencies
  import_ressuite_defaults
  cleanup_helm_artifacts
}

main "$@"
