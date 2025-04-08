#!/bin/bash

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" >/dev/null 2>&1; then
    echo "Por favor, autentique-se no gcloud primeiro usando: gcloud auth login"
    exit 1
fi

TEMP_PROJECTS_FILE="/tmp/projects_list_$$.txt"

gcloud projects list  --format="value(projectId)" > "$TEMP_PROJECTS_FILE" 2>/dev/null

echo "Conteúdo bruto da lista de projetos:"
cat "$TEMP_PROJECTS_FILE"
PROJECT_COUNT=$(grep -v '^$' "$TEMP_PROJECTS_FILE" | wc -l)
echo "Número de projetos encontrados: $PROJECT_COUNT"

OUTPUT_FILE="cloud_sql_maintenance_report_$(date +%Y%m%d_%H%M%S).txt"
echo "Relatório de Manutenções Programadas - Cloud SQL" > "$OUTPUT_FILE"
echo "Data de geração: $(date)" >> "$OUTPUT_FILE"
echo "----------------------------------------" >> "$OUTPUT_FILE"

FOUND_SQL_PROJECTS=0
TOTAL_PROJECTS=0

while IFS= read -r PROJECT; do

    [ -z "$PROJECT" ] && continue
    
    TOTAL_PROJECTS=$((TOTAL_PROJECTS + 1))
    echo "Verificando projeto $TOTAL_PROJECTS: $PROJECT"
    
    if ! gcloud config set project "$PROJECT" >/dev/null 2>&1; then
        echo "Projeto $PROJECT: Erro ao definir projeto, ignorando..."
        continue
    fi
    
    API_ENABLED=$(gcloud services list --filter="config.name=sqladmin.googleapis.com" --format="value(state)" 2>/dev/null)
    
    if [ "$API_ENABLED" != "ENABLED" ]; then
        echo "Projeto $PROJECT: Cloud SQL Admin API não habilitada, ignorando..."
        continue
    fi
    
    INSTANCES=$(gcloud sql instances list --format="value(name)" 2>/dev/null)
    
    if [ -z "$INSTANCES" ]; then
        echo "Projeto $PROJECT: API habilitada, mas nenhuma instância Cloud SQL encontrada, ignorando..."
        continue
    fi
    
    FOUND_SQL_PROJECTS=$((FOUND_SQL_PROJECTS + 1))
    echo "Projeto: $PROJECT" >> "$OUTPUT_FILE"
    echo "Instâncias encontradas:" >> "$OUTPUT_FILE"
    
    while IFS= read -r INSTANCE; do
        [ -z "$INSTANCE" ] && continue
        echo "  Analisando instância: $INSTANCE"
        
        MAINTENANCE_INFO=$(gcloud sql instances describe "$INSTANCE" --project="$PROJECT" 2>/dev/null | grep -i "startTime:" | grep "'")
        
        echo "  Instância: $INSTANCE" >> "$OUTPUT_FILE"
        if [ -n "$MAINTENANCE_INFO" ]; then
            echo "    Manutenção programada:" >> "$OUTPUT_FILE"
            echo "    $MAINTENANCE_INFO" >> "$OUTPUT_FILE"
        else
            echo "    Nenhuma manutenção programada encontrada" >> "$OUTPUT_FILE"
        fi
        echo "" >> "$OUTPUT_FILE"
    done <<< "$INSTANCES"
    
    echo "----------------------------------------" >> "$OUTPUT_FILE"
done < "$TEMP_PROJECTS_FILE"

if [ $FOUND_SQL_PROJECTS -eq 0 ]; then
    echo "Nenhum projeto com Cloud SQL encontrado na organização" >> "$OUTPUT_FILE"
    echo "Nota: Apenas $PROJECT_COUNT projeto(s) foram encontrados. Verifique permissões ou o ID da organização." >> "$OUTPUT_FILE"
fi

rm -f "$TEMP_PROJECTS_FILE"

echo "Resultado salvo em: $OUTPUT_FILE"
echo "Total de projetos analisados: $TOTAL_PROJECTS"
echo "Total de projetos com Cloud SQL criados: $FOUND_SQL_PROJECTS"