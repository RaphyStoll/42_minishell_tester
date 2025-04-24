#!/bin/bash
# ======================== INITIALISATION ========================

INVOKED_PWD=$(pwd)
export MINISHELL_PATH="${MINISHELL_PATH:-$INVOKED_PWD}"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
 
# Création et préparation du répertoire de logs
export LOG_BASE_DIR="${MINISHELL_PATH}/mstest_log_${TIMESTAMP}"
mkdir -p "$LOG_BASE_DIR"
chmod 775 "$LOG_BASE_DIR"
echo "Debug: Création du répertoire principal de logs: $LOG_BASE_DIR" > "${LOG_BASE_DIR}/init.log"
echo "Debug: pwd actuel: $(pwd)" >> "${LOG_BASE_DIR}/init.log"
echo "Debug: User actuel: $(whoami)" >> "${LOG_BASE_DIR}/init.log"

# Créer les répertoires de secours
mkdir -p "${LOG_BASE_DIR}/FALLBACK_SECTION"
mkdir -p "${LOG_BASE_DIR}/tests_sans_section"
mkdir -p "${LOG_BASE_DIR}/EMERGENCY_LOGS"
chmod -R 775 "${LOG_BASE_DIR}"

export STDOUT_LOG="${LOG_BASE_DIR}/stdout.log"
touch "$STDOUT_LOG"

export EXECUTABLE=output/minishell
RUNDIR=$HOME/42_minishell_tester

NL=$'\n'
TAB=$'\t'

# Compteurs globaux
TEST_COUNT=0
TEST_KO_OUT=0
TEST_KO_ERR=0
TEST_KO_EXIT=0
TEST_OK=0
FAILED=0
ONE=0
TWO=0
THREE=0
GOOD_TEST=0
LEAKS=0

# -----------------------  IGNORED TESTS  -----------------------
declare -A IGNORED_SECTION_ALL          # sections ignorées entièrement
declare -A IGNORED_TESTS                # clef "SECTION:NUM" -> 1
IGNORED_COUNT=0

# Charge le premier fichier ignore*.txt|md|sh présent dans le dossier d'où
# on lance mstest.
load_ignored_tests() {
    local ignore_file
    for f in "$INVOKED_PWD"/ignore*{.txt,.md,.sh}; do
        [[ -f $f ]] && { ignore_file=$f; break; }
    done
    [[ -z $ignore_file ]] && return

    while IFS= read -r line; do
        [[ $line == \#* || -z $line ]] && continue          # commentaires / vide
        line=${line//[[:space:]]/}                          # supprimer espaces
        local section=${line%%:*}; local rest=${line#*:}
        [[ -z $section || -z $rest ]] && continue
        section=$(echo "$section" | tr '[:lower:]' '[:upper:]')

        if [[ $rest == "*" ]]; then                        # ignorer toute section
            IGNORED_SECTION_ALL[$section]=1
            continue
        fi

        IFS=',' read -ra parts <<< "$rest"
        for part in "${parts[@]}"; do
            if [[ $part == *-* ]]; then                    # intervalle 4-8
                local start=${part%-*}; local end=${part#*-}
                for ((n=start;n<=end;n++)); do
                    IGNORED_TESTS["$section:$n"]=1
                done
            else                                           # numéro isolé
                IGNORED_TESTS["$section:$part"]=1
            fi
        done
    done < "$ignore_file"
}

# Renvoie 0 (=true) si le test doit être ignoré
is_ignored() {
    local section=$(echo "$1" | tr '[:lower:]' '[:upper:]')
    local num=$2
    [[ ${IGNORED_SECTION_ALL[$section]+_} ]] && return 0
    [[ ${IGNORED_TESTS["$section:$num"]+_} ]] && return 0
    return 1
}

USE_COLORS=1

TESTFILES=""
COMMAND=$1

if [[ "$1" == "--no-color" ]]; then
    USE_COLORS=0
    shift
    COMMAND=$1
fi

# ======================== FONCTIONS D'AFFICHAGE ========================

# Couleurs
COLOR_RESET="\033[0m"
COLOR_RED="\033[1;31m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_BLUE="\033[1;34m"
COLOR_PURPLE="\033[1;35m"
COLOR_CYAN="\033[1;36m"
COLOR_GRAY="\033[0;90m"

# Afficher un message avec couleur
print_color() {
    if [[ $USE_COLORS -eq 1 ]]; then
        echo -ne "$1$2$COLOR_RESET" | tee -a "${STDOUT_LOG}"
    else
        echo -ne "$2" | tee -a "${STDOUT_LOG}"
    fi
}

# Afficher l'en-tête d'une section de tests
print_section_header() {
    echo "" | tee -a "${STDOUT_LOG}"
    print_color "$COLOR_BLUE" "  🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀\n"
    print_color "$COLOR_BLUE" "  🚀                                $1                                   🚀\n"
    print_color "$COLOR_BLUE" "  🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀\n"
}

# Afficher le numéro du test
print_test_number() {
    if [[ $USE_COLORS -eq 1 ]]; then
        printf "\033[1;35m%-4s\033[m" "  $1:    "
    else
        printf "  %s:    " "$1"
    fi
    printf "  %s:    " "$1" >> "${STDOUT_LOG}"
}

# Afficher un commentaire de test
print_test_comment() {
    if [[ $USE_COLORS -eq 1 ]]; then
        echo -e "\033[1;33m        $1\033[m" | tr '\t' '    '
    else
        echo -e "        $1" | tr '\t' '    '
    fi
    echo -e "        $1" | tr '\t' '    ' >> "${STDOUT_LOG}"
}

# Afficher l'emplacement d'un test dans son fichier source
print_test_location() {
    if [[ $USE_COLORS -eq 1 ]]; then
        printf "\033[0;90m%s:%d\033[m\n" "$1" "$2"
    else
        printf "%s:%d\n" "$1" "$2"
    fi
    printf "%s:%d\n" "$1" "$2" >> "${STDOUT_LOG}"
}

# Afficher le résultat pour STDOUT (✅/❌)
print_stdout_result() {
    echo -ne "\033[1;34mSTD_OUT:\033[m " | tee -a "${STDOUT_LOG}"
    if [[ $1 -eq 0 ]]; then
        echo -ne "✅  " | tee -a "${STDOUT_LOG}"
    else
        echo -ne "❌  " | tee -a "${STDOUT_LOG}"
    fi
}

# Afficher le résultat pour STDERR (✅/❌)
print_stderr_result() {
    echo -ne "\033[1;33mSTD_ERR:\033[m " | tee -a "${STDOUT_LOG}"
    if [[ $1 -eq 0 ]]; then
        echo -ne "✅  " | tee -a "${STDOUT_LOG}"
    else
        echo -ne "❌  " | tee -a "${STDOUT_LOG}"
    fi
}

# Afficher le résultat pour EXIT_CODE (✅/❌)
print_exit_result() {
    echo -ne "\033[1;36mEXIT_CODE:\033[m " | tee -a "${STDOUT_LOG}"
    if [[ $1 -eq 0 ]]; then
        echo -ne "✅  " | tee -a "${STDOUT_LOG}"
    else
        echo -ne "❌  " | tee -a "${STDOUT_LOG}"
        if [[ $4 -eq 1 ]]; then
            echo -ne "\033[1;31m [ minishell($2)  bash($3) ]\033[m  " | tee -a "${STDOUT_LOG}"
        fi
    fi
}

# Afficher le résultat pour les fuites mémoire (✅/❌)
print_leak_result() {
    echo -ne "\033[1;36mLEAKS:\033[m " | tee -a "${STDOUT_LOG}"
    if [[ $1 -eq 0 ]]; then
        echo -ne "✅ " | tee -a "${STDOUT_LOG}"
    else
        echo -ne "❌ " | tee -a "${STDOUT_LOG}"
    fi
}

# Afficher les statistiques finales
print_stats() {
    print_color "$COLOR_RED" "🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁\n"
    print_color "$COLOR_RED" "🏁                                    RESULT                                    🏁\n"
    print_color "$COLOR_RED" "🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁🏁\n"
    
    printf "\033[1;35m%-4s\033[m" "             TOTAL TEST COUNT: $TEST_COUNT "
    printf "\033[1;32m TESTS PASSED: $GOOD_TEST\033[m "
    
    if [[ $LEAKS == 0 ]]; then
        printf "\033[1;32m LEAKING: $LEAKS\033[m "
    else
        printf "\033[1;31m LEAKING: $LEAKS\033[m "
    fi
    echo ""
    
    echo -ne "\033[1;34m                     STD_OUT:\033[m "
    if [[ $TEST_KO_OUT == 0 ]]; then
        echo -ne "\033[1;32m✓ \033[m  "
    else
        echo -ne "\033[1;31m$TEST_KO_OUT\033[m  "
    fi
    
    echo -ne "\033[1;36mSTD_ERR:\033[m "
    if [[ $TEST_KO_ERR == 0 ]]; then
        echo -ne "\033[1;32m✓ \033[m  "
    else
        echo -ne "\033[1;31m$TEST_KO_ERR\033[m  "
    fi
    
    echo -ne "\033[1;36mEXIT_CODE:\033[m "
    if [[ $TEST_KO_EXIT == 0 ]]; then
        echo -ne "\033[1;32m✓ \033[m  "
    else
        echo -ne "\033[1;31m$TEST_KO_EXIT\033[m  "
    fi
    
    echo ""
    echo -e "\033[1;33m                         TOTAL FAILED AND PASSED CASES:"
    echo -e "\033[1;31m                                     ❌ $FAILED \033[m  "
    echo -ne "\033[1;32m                                     ✅ $TEST_OK \033[m  "
    echo ""
    
    echo -e "\nLogs sauvegardés dans: ${LOG_BASE_DIR}"
}

# Afficher l'aide
print_help() {
    echo "usage: mstest [m,vm,ne,b,a] {builtins,b,parsing,pa,redirections,r,pipelines,pi,cmds,c,variables,v,corrections,co,path,syntax,s}..."
    echo "m: mandatory tests"
    echo "vm: mandatory tests with valgrind"
    echo "ne: tests without environment"
    echo "b: bonus tests"
    echo "a: mandatory and bonus tests"
    echo "d: mandatory pipe segfault test (BRUTAL)"
    echo "Starting from the second argument, their can be any number of argument specified between brackets."
    echo "You can test a specific part of your minishell by writing mstest vm builtins redirections"
    echo "If the part list is empty, everything will be tested."
}

# ======================== FONCTIONS DE LOGS ========================

# Crée le répertoire pour une section de tests et retourne son chemin
setup_section_dir() {
    local file=$1
    local base=$(basename "$file" .sh)
    local section=${base#*_}
    local section_upper=$(echo "$section" | tr '[:lower:]' '[:upper:]')
    
    # Utiliser directement le répertoire de secours qui fonctionne
    local section_dir="${LOG_BASE_DIR}/FALLBACK_${section_upper}"
    mkdir -p "$section_dir"
    chmod 775 "$section_dir"
    
    echo "Test" > "${section_dir}/test_perm.txt"
    echo "Debug: Utilisation directe du répertoire de secours: $section_dir" >> "${LOG_BASE_DIR}/debug.log"
    
    echo -e "\n[INFO] Testing section: ${section_upper}" | tee -a "${STDOUT_LOG}"
    echo "$section_dir"
}

# Sauvegarde le log d'un test dans un fichier
save_failed_test_log() {
    local test_num=$1
    local section_dir=$2
    local input="$3"
    local exit_bash=$4
    local exit_minishell=$5
    local out_bash=$(cat tmp_out_bash 2>/dev/null || echo "Impossible de lire tmp_out_bash")
    local out_minishell=$(cat tmp_out_minishell 2>/dev/null || echo "Impossible de lire tmp_out_minishell")
    local err_bash=$(cat tmp_err_bash 2>/dev/null || echo "Impossible de lire tmp_err_bash")
    local err_minishell=$(cat tmp_err_minishell 2>/dev/null || echo "Impossible de lire tmp_err_minishell")
    
    # Vérifier le répertoire de log
    if [ ! -d "${LOG_BASE_DIR}" ]; then
        mkdir -p "${LOG_BASE_DIR}"
    fi
    
    echo "Debug: Tentative de création du log pour le test $test_num dans $section_dir" >> "${LOG_BASE_DIR}/save_debug.log"
    echo "Debug: pwd=$(pwd)" >> "${LOG_BASE_DIR}/save_debug.log"
    
    # Assurer la validité du répertoire de section
    if [ -z "$section_dir" ]; then
        echo "Debug: ERREUR - section_dir est vide!" >> "${LOG_BASE_DIR}/save_debug.log"
        
        # Essayer de récupérer la section à partir du nom de test
        local test_section=$(echo "$input" | grep -o '/[a-zA-Z0-9_]*/[a-zA-Z0-9_]*\.sh' | awk -F/ '{print $2}' | head -1)
        if [ -n "$test_section" ]; then
            local section_upper=$(echo "$test_section" | tr '[:lower:]' '[:upper:]')
            section_dir="${LOG_BASE_DIR}/FALLBACK_${section_upper}"
        else
            section_dir="${LOG_BASE_DIR}/tests_sans_section"
        fi
        
        mkdir -p "$section_dir"
        chmod 775 "$section_dir"
    fi
    
    mkdir -p "$section_dir" 2>> "${LOG_BASE_DIR}/save_debug.log"
    if [ ! -d "$section_dir" ] || [ ! -w "$section_dir" ]; then
        section_dir="${LOG_BASE_DIR}/tests_sans_section"
        mkdir -p "$section_dir" 
        chmod 775 "$section_dir"
    fi
    
    local log_file="${section_dir}/test${test_num}.log"
    echo "Debug: Tentative d'écriture du log dans: $log_file" >> "${LOG_BASE_DIR}/save_debug.log"
    
    # Vérifier les permissions
    echo "Test" > "${section_dir}/test_perm.txt"
    sync
    
    if [ ! -f "${section_dir}/test_perm.txt" ]; then
        section_dir="${LOG_BASE_DIR}/tests_sans_section"
        mkdir -p "$section_dir"
        chmod 775 "$section_dir"
        log_file="${section_dir}/test${test_num}.log"
    fi
    
    # Écrire le contenu du log
    {
        echo "============= TEST #${test_num} ÉCHOUÉ ============="
        echo "Input :"
        echo "$input"
        echo ""
        
        echo "--------- STDOUT ---------"
        echo "Bash :"
        echo "$out_bash"
        echo ""
        echo "Minishell :"
        echo "$out_minishell"
        echo ""
        
        echo "--------- STDERR ---------"
        echo "Bash :"
        echo "$err_bash"
        echo ""
        echo "Minishell :"
        echo "$err_minishell"
        echo ""
        
        echo "--------- EXIT CODE ---------"
        echo "Bash : $exit_bash"
        echo "Minishell : $exit_minishell"
        echo ""
        echo "=================================="
    } > "$log_file"
    sync
    
    # Vérifier la création du fichier
    if [ -f "$log_file" ]; then
        echo "Debug: Fichier créé avec succès: $log_file" >> "${LOG_BASE_DIR}/save_debug.log"
        ls -la "$log_file" >> "${LOG_BASE_DIR}/save_debug.log" 2>&1
    else
        echo "Debug: ERREUR - Impossible de créer le fichier: $log_file" >> "${LOG_BASE_DIR}/save_debug.log"
        mkdir -p "${LOG_BASE_DIR}/EMERGENCY_LOGS" 2>/dev/null
        echo "TEST #${test_num} ÉCHOUÉ" > "${LOG_BASE_DIR}/EMERGENCY_LOGS/test${test_num}.log"
    fi
}

# Écrit le résumé d'une section de tests dans un fichier
write_section_summary() {
    local section_dir=$1
    local total_tests=$2
    local with_leaks=$3
    
    {
        echo -e "\n[RÉSUMÉ SECTION: $(basename $section_dir)]"
        echo "Total tests: $total_tests"
        echo "Tests réussis: $GOOD_TEST"
        echo "Tests échoués: $((total_tests-GOOD_TEST))"
        if [[ $with_leaks -eq 1 ]]; then
            echo "Tests avec fuites mémoire: $LEAKS"
        fi
        echo "---------------------------"
    } >> "${section_dir}/summary.log"
}

# ======================== FONCTIONS D'EXÉCUTION DE COMMANDES ========================

# Exécute une commande dans minishell et bash et retourne les codes de sortie
run_command() {
    local input=$1
    local use_env=$2
    
    if [[ $use_env -eq 0 ]]; then
        # Sans environnement
        echo -n "$input" | env -i $MINISHELL_PATH/$EXECUTABLE 2>tmp_err_minishell >tmp_out_minishell
        local exit_minishell=$?
        echo -n "enable -n .$NL$input" | env -i bash 2>tmp_err_bash >tmp_out_bash
        local exit_bash=$?
    else
        # Avec environnement
        echo -n "$input" | $MINISHELL_PATH/$EXECUTABLE 2>tmp_err_minishell >tmp_out_minishell
        local exit_minishell=$?
        echo -n "enable -n .$NL$input" | bash 2>tmp_err_bash >tmp_out_bash
        local exit_bash=$?
    fi
    
    echo "$exit_minishell $exit_bash"
}

# Sanitize outputs before comparing: strip ANSI codes and drop lines that echo the original command
sanitize_output() {
    local in_file=$1
    local orig_input="$2"
    local pattern_file
    pattern_file=$(mktemp)

    # Build a pattern file containing every line of the original input (empty lines removed)
    printf "%s\n" "$orig_input" | sed '/^$/d' > "$pattern_file"

    # 1) remove ANSI escape sequences
    # 2) filter out any line that exactly matches one of the original input lines
    #    (e.g., minishell echoing the command)
    sed -e 's/\x1B\[[0-9;]*[A-Za-z]//g' "$in_file" | grep -Fvxf "$pattern_file"

    rm -f "$pattern_file"
}

# Vérifie la différence de sortie standard entre minishell et bash
check_stdout() {
    local orig_input="$1"

    sanitize_output tmp_out_minishell "$orig_input" > tmp_out_minishell.clean
    sanitize_output tmp_out_bash      "$orig_input" > tmp_out_bash.clean

    if ! diff -q tmp_out_minishell.clean tmp_out_bash.clean >/dev/null; then
        rm -f tmp_out_minishell.clean tmp_out_bash.clean
        print_stdout_result 1
        ((TEST_KO_OUT++))
        ((FAILED++))
        return 1
    else
        rm -f tmp_out_minishell.clean tmp_out_bash.clean
        print_stdout_result 0
        ((TEST_OK++))
        ((ONE++))
        return 0
    fi
}

# Vérifie la différence de sortie d'erreur entre minishell et bash
check_stderr() {
    if [[ -s tmp_err_minishell && ! -s tmp_err_bash ]] || [[ ! -s tmp_err_minishell && -s tmp_err_bash ]]; then
        print_stderr_result 1
        ((TEST_KO_ERR++))
        ((FAILED++))
        return 1
    else
        print_stderr_result 0
        ((TEST_OK++))
        ((TWO++))
        return 0
    fi
}

# Vérifie les différences de code de sortie entre minishell et bash
check_exitcode() {
    local exit_minishell=$1
    local exit_bash=$2
    local verbose=$3
    
    if [[ $exit_minishell != $exit_bash ]]; then
        print_exit_result 1 $exit_minishell $exit_bash $verbose
        ((TEST_KO_EXIT++))
        ((FAILED++))
        return 1
    else
        print_exit_result 0 $exit_minishell $exit_bash $verbose
        ((TEST_OK++))
        ((THREE++))
        return 0
    fi
}

# Vérifie les fuites mémoire avec valgrind
check_leaks() {
    local input=$1
    
    echo -n "$input" | valgrind --leak-check=full --show-leak-kinds=all --track-origins=yes --verbose --log-file=tmp_valgrind-out.txt $MINISHELL_PATH/$EXECUTABLE 2>/dev/null >/dev/null
    
    # Analyse des résultats de valgrind
    local definitely_lost=$(cat tmp_valgrind-out.txt | grep "definitely lost:" | awk 'END{print $4}')
    local possibly_lost=$(cat tmp_valgrind-out.txt | grep "possibly lost:" | awk 'END{print $4}')
    local indirectly_lost=$(cat tmp_valgrind-out.txt | grep "indirectly lost:" | awk 'END{print $4}')
    local all_blocks_freed=$(cat tmp_valgrind-out.txt | grep "All heap blocks were freed -- no leaks are possible")
    
    if [ "$definitely_lost" != "0" ] || [ "$possibly_lost" != "0" ] || [ "$indirectly_lost" != "0" ] && [[ -z "$all_blocks_freed" ]]; then
        print_leak_result 1
        ((LEAKS++))
        return 1
    else
        print_leak_result 0
        return 0
    fi
}

# Met à jour le statut de réussite/échec d'un test
update_test_status() {
    if [[ $ONE == 1 && $TWO == 1 && $THREE == 1 ]]; then
        ((GOOD_TEST++))
        ((ONE--))
        ((TWO--))
        ((THREE--))
    else
        ONE=0
        TWO=0
        THREE=0
    fi
}

# ======================== FONCTION PRINCIPALE DE TEST ========================

# Traite un fichier de test et exécute tous les tests qu'il contient
process_test_file() {
    local file=$1
    local with_env=$2
    local check_mem_leaks=$3
    local verbose_exit=$4
    
    IFS=''
    local i=1
    local end_of_file=0
    local line_count=0
    local INPUT=""
    
    # Extraire le nom de section directement
    local base=$(basename "$file" .sh)
    local section=${base#*_}
    local section_upper=$(echo "$section" | tr '[:lower:]' '[:upper:]')
    
    # Utiliser directement le répertoire de secours spécifique à la section
    local section_dir="${LOG_BASE_DIR}/FALLBACK_${section_upper}"
    mkdir -p "$section_dir"
    chmod 775 "$section_dir"
    
    echo -e "\n[INFO] Testing section: ${section_upper}" | tee -a "${STDOUT_LOG}"
    
    while [[ $end_of_file == 0 ]]; do
        read -r line
        end_of_file=$?
        ((line_count++))
        
        # Ignorer les commentaires et lignes vides
        if [[ $line == \#* ]] || [[ $line == "" ]]; then
            if [[ $line == "#"[[:blank:]]*[[:blank:]]"#" ]]; then
                print_test_comment "$line"
            fi
            continue
        else
            # Afficher le numéro du test
            print_test_number "$i"
            local tmp_line_count=$line_count
            
            # Lire l'entrée du test jusqu'à un commentaire ou une ligne vide
            while [[ $end_of_file == 0 ]] && [[ $line != \#* ]] && [[ $line != "" ]]; do
                INPUT+="$line$NL"
                read -r line
                end_of_file=$?
                ((line_count++))
            done
            
            # Sauvegarder l'entrée originale
            local ORIGINAL_INPUT="$INPUT"

			# Test ignoré ?
            if is_ignored "$section_upper" "$i"; then
                if [[ $USE_COLORS -eq 1 ]]; then
                    echo -e "\033[0;90m⏭️  IGNORÉ\033[m" | tee -a "${STDOUT_LOG}"
                else
                    echo "IGNORÉ" | tee -a "${STDOUT_LOG}"
                fi
                ((IGNORED_COUNT++))
                print_test_location "$file" "$tmp_line_count"
                INPUT=""
                ((i++))
                ((TEST_COUNT++))
                continue
            fi

            # Exécuter les commandes
            local exit_values=$(run_command "$INPUT" $with_env)
            local exit_minishell=$(echo $exit_values | cut -d' ' -f1)
            local exit_bash=$(echo $exit_values | cut -d' ' -f2)
            
            # Vérifier les sorties
            local failed_stdout=0
            local failed_stderr=0
            local failed_exit=0
            local has_leaks=0
            
            check_stdout "$ORIGINAL_INPUT" || failed_stdout=1
            check_stderr || failed_stderr=1
            check_exitcode $exit_minishell $exit_bash $verbose_exit || failed_exit=1
            
            # Vérifier les fuites de mémoire si demandé
            if [[ $check_mem_leaks -eq 1 ]]; then
                check_leaks "$INPUT" || has_leaks=1
                
                if [[ $has_leaks -eq 1 ]]; then
                    cp tmp_valgrind-out.txt "${section_dir}/test${i}_valgrind.log"
                fi
            fi
            
            # Mettre à jour le statut du test
            update_test_status
            
            # Sauvegarder le détail du test
            echo "Test $i: stdout=$failed_stdout stderr=$failed_stderr exit=$failed_exit leaks=$has_leaks" >> "${LOG_BASE_DIR}/debug.log"
            save_failed_test_log "$i" "$section_dir" "$ORIGINAL_INPUT" "$exit_bash" "$exit_minishell"
            echo "Log file created: ${section_dir}/test${i}.log" >> "${LOG_BASE_DIR}/debug_files.log"
            
            print_test_location "$file" "$tmp_line_count"
            
            # Réinitialiser et incrémenter les compteurs
            INPUT=""
            ((i++))
            ((TEST_COUNT++))
        fi
    done < "$file"
    
    # Écrire le résumé de la section
    write_section_summary "$section_dir" $((i-1)) $check_mem_leaks
}

# ======================== FONCTIONS DE TEST SPÉCIFIQUES ========================

# Tests standards avec environnement normal
test_from_file() {
    process_test_file "$1" 1 0 0  # avec env, sans vérif fuites, format simple
}

# Tests avec vérification des fuites mémoire
test_leaks() {
    process_test_file "$1" 1 1 1  # avec env, avec vérif fuites, format verbeux
}

# Tests sans environnement
test_without_env() {
    process_test_file "$1" 0 0 1  # sans env, sans vérif fuites, format verbeux
}

# Tester tous les fichiers pour le mode mandatory
test_mandatory() {
    local FILES="${RUNDIR}/cmds/mand/*"
    for file in $FILES; do
        if [[ $TESTFILES =~ $file ]] || [ -z $TESTFILES ]; then
            test_from_file $file
        fi
    done
}

# Tester tous les fichiers pour le mode mandatory avec vérification de fuites
test_mandatory_leaks() {
    local FILES="${RUNDIR}/cmds/mand/*"
    for file in $FILES; do
        if [[ $TESTFILES =~ $file ]] || [ -z $TESTFILES ]; then
            test_leaks $file
        fi
    done
}

# Tester tous les fichiers pour le mode sans environnement
test_no_env() {
    local FILES="${RUNDIR}/cmds/no_env/*"
    for file in $FILES; do
        if [[ $TESTFILES =~ $file ]] || [ -z $TESTFILES ]; then
            test_without_env $file
        fi
    done
}

# Tester tous les fichiers pour le mode bonus
test_bonus() {
    local FILES="${RUNDIR}/cmds/bonus/*"
    for file in $FILES; do
        if [[ $TESTFILES =~ $file ]] || [ -z $TESTFILES ]; then
            test_from_file $file
        fi
    done
}

# Tester tous les fichiers pour le mode mini_death
test_mini_death() {
    local FILES="${RUNDIR}/cmds/mini_death/*"
    for file in $FILES; do
        if [[ $TESTFILES =~ $file ]] || [ -z $TESTFILES ]; then
            test_from_file $file
        fi
    done
}

# Vérifier si minishell est compilé
check_minishell_exists() {
    if [[ ! -f $MINISHELL_PATH/$EXECUTABLE ]]; then
        echo -e "\033[1;31m# **************************************************************************** #"
        echo "#                            MINISHELL NOT COMPILED                            #"
        echo "#                              TRY TO COMPILE ...                              #"
        echo -e "# **************************************************************************** #\033[m"
        make -C $MINISHELL_PATH
        if [[ ! -f $MINISHELL_PATH/$EXECUTABLE ]]; then
            echo -e "\033[1;31mCOMPILING FAILED\033[m" && exit 1
        fi
    fi
}

# ======================== FONCTION PRINCIPALE ========================

# ======================== FONCTION PRINCIPALE ========================

main() {
    # Traiter les arguments supplémentaires pour les tests spécifiques
    while [ -n "$2" ]; do
        case $2 in
            "builtins" | "b") 
                TESTFILES+="${RUNDIR}/cmds/mand/1_builtins.sh"
                ;;
            "parsing" | "pa") 
                TESTFILES+=" ${RUNDIR}/cmds/mand/0_compare_parsing.sh"
                TESTFILES+=" ${RUNDIR}/cmds/mand/10_parsing_hell.sh"
                ;;
            "redirections" | "r")
                TESTFILES+=" ${RUNDIR}/cmds/mand/1_redirs.sh"
                ;;
            "pipelines" | "pi")
                TESTFILES+=" ${RUNDIR}/cmds/mand/1_pipelines.sh"
                ;;
            "cmds" | "c")
                TESTFILES+=" ${RUNDIR}/cmds/mand/1_scmds.sh"
                ;;
            "variables" | "v")
                TESTFILES+=" ${RUNDIR}/cmds/mand/1_variables.sh"
                ;;
            "corrections" | "co")
                TESTFILES+=" ${RUNDIR}/cmds/mand/2_correction.sh"
                ;;
            "path")
                TESTFILES+=" ${RUNDIR}/cmds/mand/2_path_check.sh"
                ;;
            "syntax" | "s")
                TESTFILES+=" ${RUNDIR}/cmds/mand/8_syntax_errors.sh"
                ;;
        esac
        shift
    done
    set "$COMMAND"
    
    # Vérifier si minishell est compilé
    check_minishell_exists
    
    load_ignored_tests

    # Exécuter les tests selon le mode demandé
    case $1 in
        "m")
            print_section_header "MANDATORY"
            test_mandatory
            ;;
        "vm")
            print_section_header "MANDATORY_LEAKS"
            test_mandatory_leaks
            ;;
        "ne")
            print_section_header "NO_ENV"
            test_no_env
            ;;
        "b")
            print_section_header "BONUS"
            test_bonus
            ;;
        "a")
            print_section_header "ALL TESTS"
            test_mandatory
            test_bonus
            ;;
        "d")
            print_section_header "MINI_DEATH"
            test_mini_death
            ;;
        "-f")
            if [[ ! -f $2 ]]; then
                echo "\"$2\" FILE NOT FOUND"
            else
                test_from_file $2
            fi
            ;;
        *)
            print_help
            exit 0
            ;;
    esac
    # Archiver les logs qu’on ne veut plus en racine
	ARCHIVE_DIR="${LOG_BASE_DIR}/archived_logs"
	mkdir -p "$ARCHIVE_DIR"
	mv "$LOG_BASE_DIR"/init.log \
   	   "$LOG_BASE_DIR"/save_debug.log \
   	   "$LOG_BASE_DIR"/debug_files.log \
   	   "$LOG_BASE_DIR"/tests_sans_section \
   	   "$LOG_BASE_DIR"/FALLBACK_SECTION \
   	   "$LOG_BASE_DIR"/EMERGENCY_LOGS \
   	   "$ARCHIVE_DIR"
    # Nettoyer et afficher les statistiques
    rm -rf test
    print_stats
}

# Lancer le script
main "$@"

# Clean all tmp files
[[ $1 != "-f" ]] && rm -f tmp_*