#!/bin/bash

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" >/dev/null 2>&1; then
    echo "Por favor, autentique-se no gcloud primeiro usando: gcloud auth login"
    exit 1
fi

TEMP_PROJECTS_FILE="/tmp/projects_list_$$.txt"

gcloud projects list  --format="value(projectId)" > "$TEMP_PROJECTS_FILE" 2>/dev/null

echo "Temporary file with projects list:"
cat "$TEMP_PROJECTS_FILE"
PROJECT_COUNT=$(grep -v '^$' "$TEMP_PROJECTS_FILE" | wc -l)
echo "Projects Founded: $PROJECT_COUNT"

OUTPUT_FILE="cloud_sql_maintenance_report_$(date +%Y%m%d_%H%M%S).txt"
echo "Relatório de Manutenções Programadas - Cloud SQL" > "$OUTPUT_FILE"
echo "Data de geração: $(date)" >> "$OUTPUT_FILE"
echo "----------------------------------------" >> "$OUTPUT_FILE"

FOUND_SQL_PROJECTS=0
TOTAL_PROJECTS=0

while IFS= read -r PROJECT; do

    [ -z "$PROJECT" ] && continue
    
    TOTAL_PROJECTS=$((TOTAL_PROJECTS + 1))
    echo "Verifing project $TOTAL_PROJECTS: $PROJECT"
    
    if ! gcloud config set project "$PROJECT" >/dev/null 2>&1; then
        echo "Project $PROJECT: Error defining project, ignoring."
        continue
    fi
    
    API_ENABLED=$(gcloud services list --filter="config.name=sqladmin.googleapis.com" --format="value(state)" 2>/dev/null)
    
    if [ "$API_ENABLED" != "ENABLED" ]; then
        echo "Projeto $PROJECT: Cloud SQL Admin API isn't enabled, ignoring."
        continue
    fi
    
    INSTANCES=$(gcloud sql instances list --format="value(name)" 2>/dev/null)
    
    if [ -z "$INSTANCES" ]; then
        echo "Projeto $PROJECT: API enabled, but any Cloud SQL instance founded, ignoring."
        continue
    fi
    
    FOUND_SQL_PROJECTS=$((FOUND_SQL_PROJECTS + 1))
    echo "Project: $PROJECT" >> "$OUTPUT_FILE"
    echo "Founded Instances:" >> "$OUTPUT_FILE"
    
    while IFS= read -r INSTANCE; do
        [ -z "$INSTANCE" ] && continue
        echo "  Analyzing instances: $INSTANCE"
        
        MAINTENANCE_INFO=$(gcloud sql instances describe "$INSTANCE" --project="$PROJECT" 2>/dev/null | grep -i "startTime:" | grep "'")
        
        echo "  Instância: $INSTANCE" >> "$OUTPUT_FILE"
        if [ -n "$MAINTENANCE_INFO" ]; then
            echo "    Scheduled Maintance:" >> "$OUTPUT_FILE"
            echo "    $MAINTENANCE_INFO" >> "$OUTPUT_FILE"
        else
            echo "    Any Scheduled Maintance founded" >> "$OUTPUT_FILE"
        fi
        echo "" >> "$OUTPUT_FILE"
    done <<< "$INSTANCES"
    
    echo "----------------------------------------" >> "$OUTPUT_FILE"
done < "$TEMP_PROJECTS_FILE"

if [ $FOUND_SQL_PROJECTS -eq 0 ]; then
    echo "Any project with Cloud SQL founded on organization" >> "$OUTPUT_FILE"
    echo "Note: Only $PROJECT_COUNT projects were founded. Verify permission and try again." >> "$OUTPUT_FILE"
fi

rm -f "$TEMP_PROJECTS_FILE"

echo "Results saved on: $OUTPUT_FILE"
echo "Total of analized projects: $TOTAL_PROJECTS"
echo "Total of projects with Cloud SQL instances: $FOUND_SQL_PROJECTS"
