#!/bin/bash

TEST_NAME="prueba_credito"
INPUT_FILE="inputs/multipleInput.jsonl"
OUTPUT_DIR="target"
LOG_FILE="noir_bench.log"

# Contadores
passed=0
failed=0
constraint_errors=0

echo "===== INICIO BENCHMARK NOIR =====" | tee $LOG_FILE
echo "Circuito: $TEST_NAME" | tee -a $LOG_FILE
echo "Archivo de pruebas: $INPUT_FILE" | tee -a $LOG_FILE
start_total=$(date +%s.%N)

# Compilar circuito
echo -e "\n[1/4] 🔄 Compilando circuito..." | tee -a $LOG_FILE
if ! nargo execute >> $LOG_FILE 2>&1; then
    echo "❌ Error en compilación" | tee -a $LOG_FILE
    exit 1
fi
echo "✅ Compilación completada" | tee -a $LOG_FILE

# Preparar backend
echo -e "\n[2/4] ⚙️ Preparando backend..." | tee -a $LOG_FILE
if ! bb prove -b ./target/${TEST_NAME}.json -w ./target/${TEST_NAME}.gz -o ./target >> $LOG_FILE 2>&1 || \
   ! bb write_vk -b ./target/${TEST_NAME}.json -o ./target >> $LOG_FILE 2>&1; then
    echo "❌ Error en setup del backend" | tee -a $LOG_FILE
    exit 1
fi
echo "✅ Backend configurado" | tee -a $LOG_FILE

# Ejecutar pruebas
total_proof=0
total_verify=0
test_count=0
TEMP_INPUTS_DIR="$OUTPUT_DIR/temp_inputs"
mkdir -p "$TEMP_INPUTS_DIR"

echo -e "\n[3/4] 🧪 Ejecutando pruebas desde $INPUT_FILE..." | tee -a $LOG_FILE
line_number=0

while IFS= read -r line; do
    line_number=$((line_number + 1))
    test_count=$((test_count + 1))
    test_file="test_${line_number}.json"
    
    echo "$line" > "$TEMP_INPUTS_DIR/$test_file"
    echo -e "\n● PRUEBA $test_count: $test_file" | tee -a $LOG_FILE
    echo "📋 Input: $line" | tee -a $LOG_FILE

    # Generar Prover.toml con valores por defecto
    echo "" > Prover.toml
    jq -r 'to_entries[] | "\(.key) = \(.value)"' "$TEMP_INPUTS_DIR/$test_file" >> Prover.toml

    # Rellenar campos que falten
    grep -q 'cuotas' Prover.toml || echo 'cuotas = "6"' >> Prover.toml
    grep -q 'gastos' Prover.toml || echo 'gastos = "800"' >> Prover.toml
    grep -q 'ingresos' Prover.toml || echo 'ingresos = "3000"' >> Prover.toml
    grep -q 'prestamo' Prover.toml || echo 'prestamo = "4800"' >> Prover.toml

    echo "🔄 Input convertido y completado con valores por defecto" | tee -a $LOG_FILE

    proof_status=""
    verify_status=""
    proof_time=0
    verify_time=0

    start=$(date +%s.%N)
    echo "⚡ Ejecutando nargo..." | tee -a $LOG_FILE

    if nargo execute >> $LOG_FILE 2>&1; then
        if bb prove -b ./target/${TEST_NAME}.json -w ./target/${TEST_NAME}.gz -o ./target >> $LOG_FILE 2>&1; then
            proof_status="✅"
        else
            proof_status="❌ (Error en generación de prueba)"
        fi
    else
        proof_status="❌ (Restricción no satisfecha)"
        ((constraint_errors++))
    fi
    end=$(date +%s.%N)
    proof_time=$(echo "$end - $start" | bc)
    total_proof=$(echo "$total_proof + $proof_time" | bc)

    if [ "$proof_status" == "✅" ]; then
        start=$(date +%s.%N)
        echo "🔍 Verificando prueba..." | tee -a $LOG_FILE
        if bb verify -k ./target/vk -p ./target/proof >> $LOG_FILE 2>&1; then
            verify_status="✅"
            ((passed++))
        else
            verify_status="❌ (Fallo en verificación)"
            ((failed++))
        fi
        end=$(date +%s.%N)
        verify_time=$(echo "$end - $start" | bc)
        total_verify=$(echo "$total_verify + $verify_time" | bc)
    else
        verify_status="N/A"
        ((failed++))
    fi

    echo "------------------------" | tee -a $LOG_FILE
    echo "⏱️ Tiempos para $test_file:" | tee -a $LOG_FILE
    echo "  Generación de prueba: $proof_time seg [$proof_status]" | tee -a $LOG_FILE
    echo "  Verificación: $verify_time seg [$verify_status]" | tee -a $LOG_FILE
    echo "Estado: $([ "$verify_status" == "✅" ] && echo "PASÓ" || echo "FALLÓ")" | tee -a $LOG_FILE

    rm -f Prover.toml
    rm -f "$TEMP_INPUTS_DIR/$test_file"

done < "$INPUT_FILE"

rmdir "$TEMP_INPUTS_DIR"

# Resultados finales
end_total=$(date +%s.%N)
total_time=$(echo "$end_total - $start_total" | bc)
avg_proof=$(echo "scale=3; $total_proof / $test_count" | bc)
avg_verify=0
[ $passed -gt 0 ] && avg_verify=$(echo "scale=3; $total_verify / $passed" | bc)

echo -e "\n[4/4] 📊 RESULTADOS FINALES" | tee -a $LOG_FILE
echo "============================" | tee -a $LOG_FILE
echo "🔢 Total de pruebas: $test_count" | tee -a $LOG_FILE
echo "✅ Pruebas pasadas: $passed" | tee -a $LOG_FILE
echo "❌ Pruebas fallidas: $failed" | tee -a $LOG_FILE
echo "⚠️ Errores de restricción: $constraint_errors" | tee -a $LOG_FILE
echo "⏳ Tiempo total: $total_time seg" | tee -a $LOG_FILE
echo "📈 Promedios:" | tee -a $LOG_FILE
echo "  Generación de prueba: $avg_proof seg/prueba (todos los casos)" | tee -a $LOG_FILE
echo "  Verificación: $avg_verify seg/prueba (solo exitosas)" | tee -a $LOG_FILE
echo "============================" | tee -a $LOG_FILE
echo "✅ Benchmark completado" | tee -a $LOG_FILE

exit 0
