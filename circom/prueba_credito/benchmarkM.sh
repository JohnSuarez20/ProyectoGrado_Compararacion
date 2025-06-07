#!/bin/bash

CIRCUIT_NAME="prueba_credito"
INPUT_FILE="inputs/multipleInput.jsonl"
BUILD_DIR="build"
LOG_FILE="circom_bench.log"

# Contadores
passed=0
failed=0
constraint_errors=0
successful_witness=0
successful_proof=0
successful_verify=0

# Inicialización
echo "===== INICIO BENCHMARK CIRCOM =====" | tee $LOG_FILE
echo "Circuito: $CIRCUIT_NAME" | tee -a $LOG_FILE
echo "Archivo de pruebas: $INPUT_FILE" | tee -a $LOG_FILE
start_total=$(date +%s.%N)

# Validación de rutas
if [ ! -f "$INPUT_FILE" ]; then
    echo "❌ El archivo de entrada $INPUT_FILE no existe." | tee -a $LOG_FILE
    exit 1
fi
if [ ! -d "$BUILD_DIR" ]; then
    echo "❌ El directorio de build $BUILD_DIR no existe." | tee -a $LOG_FILE
    exit 1
fi

# 1. Compilación
echo -e "\n[1/5] 🔄 Compilando circuito..." | tee -a $LOG_FILE
[ ! -f "$BUILD_DIR/$CIRCUIT_NAME.r1cs" ] && {
    if ! circom circuits/$CIRCUIT_NAME.circom --r1cs --wasm --sym -o $BUILD_DIR >> $LOG_FILE 2>&1; then
        echo "❌ Error en compilación" | tee -a $LOG_FILE
        exit 1
    fi
    echo "✅ Compilación completada" | tee -a $LOG_FILE
} || {
    echo "✅ Circuito ya compilado (usando caché)" | tee -a $LOG_FILE
}

# 2. Trusted Setup Fase 1
echo -e "\n[2/5] ⚙️ Trusted Setup Fase 1..." | tee -a $LOG_FILE
[ ! -f "pot12_final.ptau" ] && {
    if ! snarkjs powersoftau new bn128 12 pot12_0000.ptau -v >> $LOG_FILE 2>&1 || \
       ! snarkjs powersoftau prepare phase2 pot12_0000.ptau pot12_final.ptau -v >> $LOG_FILE 2>&1; then
        echo "❌ Error en Trusted Setup Fase 1" | tee -a $LOG_FILE
        exit 1
    fi
    echo "✅ Trusted Setup Fase 1 completado" | tee -a $LOG_FILE
} || {
    echo "✅ Trusted Setup Fase 1 ya existe (usando caché)" | tee -a $LOG_FILE
}

# 3. Trusted Setup Fase 2
echo -e "\n[3/5] ⚙️ Trusted Setup Fase 2..." | tee -a $LOG_FILE
[ ! -f "$BUILD_DIR/circuit_0000.zkey" ] && {
    if ! snarkjs groth16 setup $BUILD_DIR/$CIRCUIT_NAME.r1cs pot12_final.ptau $BUILD_DIR/circuit_0000.zkey >> $LOG_FILE 2>&1 || \
       ! snarkjs zkey export verificationkey $BUILD_DIR/circuit_0000.zkey $BUILD_DIR/verification_key.json >> $LOG_FILE 2>&1; then
        echo "❌ Error en Trusted Setup Fase 2" | tee -a $LOG_FILE
        exit 1
    fi
    echo "✅ Trusted Setup Fase 2 completado" | tee -a $LOG_FILE
} || {
    echo "✅ Trusted Setup Fase 2 ya existe (usando caché)" | tee -a $LOG_FILE
}

# 4. Ejecución de pruebas
total_witness=0
total_proof=0
total_verify=0
test_count=0

echo -e "\n[4/5] 🧪 Ejecutando pruebas desde $INPUT_FILE..." | tee -a $LOG_FILE
TEMP_INPUTS_DIR="$BUILD_DIR/temp_inputs"
mkdir -p "$TEMP_INPUTS_DIR"

line_number=0
while IFS= read -r line; do
    line_number=$((line_number + 1))
    test_count=$((test_count + 1))
    test_file="test_${line_number}.json"
    echo "$line" > "$TEMP_INPUTS_DIR/$test_file"

    echo -e "\n● PRUEBA $test_count: $test_file" | tee -a $LOG_FILE
    echo "📋 Input: $line" | tee -a $LOG_FILE

    witness_status="❌ (No ejecutada)"
    proof_status="❌ (No ejecutada)"
    verify_status="❌ (No ejecutada)"
    witness_time=0
    proof_time=0
    verify_time=0

    # Witness
    start=$(date +%s.%N)
    echo "⚡ Generando witness..." | tee -a $LOG_FILE
    if node $BUILD_DIR/${CIRCUIT_NAME}_js/generate_witness.js \
        $BUILD_DIR/${CIRCUIT_NAME}_js/$CIRCUIT_NAME.wasm \
        "$TEMP_INPUTS_DIR/$test_file" \
        $BUILD_DIR/witness_${test_file%.*}.wtns >> $LOG_FILE 2>&1; then
        witness_status="✅"
        successful_witness=$((successful_witness + 1))
    else
        witness_status="❌ (Error en generación de witness)"
        ((constraint_errors++))
        ((failed++))
    fi

    end=$(date +%s.%N)
    witness_time=$(echo "$end - $start" | bc)
    [ "$witness_status" == "✅" ] && total_witness=$(echo "$total_witness + $witness_time" | bc)

    # Prueba
    if [ "$witness_status" == "✅" ]; then
        start=$(date +%s.%N)
        echo "⚡ Generando prueba..." | tee -a $LOG_FILE
        if snarkjs groth16 prove $BUILD_DIR/circuit_0000.zkey \
            $BUILD_DIR/witness_${test_file%.*}.wtns \
            $BUILD_DIR/proof_${test_file%.*}.json \
            $BUILD_DIR/public_${test_file%.*}.json >> $LOG_FILE 2>&1; then
            proof_status="✅"
            successful_proof=$((successful_proof + 1))
        else
            proof_status="❌ (Error en generación de prueba)"
            ((failed++))
        fi
        end=$(date +%s.%N)
        proof_time=$(echo "$end - $start" | bc)
        [ "$proof_status" == "✅" ] && total_proof=$(echo "$total_proof + $proof_time" | bc)
    else
        proof_status="N/A (Witness falló)"
    fi

    # Verificación
    if [ "$proof_status" == "✅" ]; then
        start=$(date +%s.%N)
        echo "🔍 Verificando prueba..." | tee -a $LOG_FILE
        result=$(snarkjs groth16 verify $BUILD_DIR/verification_key.json \
                    $BUILD_DIR/public_${test_file%.*}.json \
                    $BUILD_DIR/proof_${test_file%.*}.json 2>> $LOG_FILE)

        if echo "$result" | grep -q "OK!"; then
            verify_status="✅"
            successful_verify=$((successful_verify + 1))
            ((passed++))
        else
            verify_status="❌ (Fallo en verificación)"
            ((failed++))
        fi
        end=$(date +%s.%N)
        verify_time=$(echo "$end - $start" | bc)
        [ "$verify_status" == "✅" ] && total_verify=$(echo "$total_verify + $verify_time" | bc)
    else
        verify_status="N/A (Proof falló)"
    fi

    echo "------------------------" | tee -a $LOG_FILE
    echo "⏱️ Tiempos para $test_file:" | tee -a $LOG_FILE
    echo "  Witness: $witness_time seg [$witness_status]" | tee -a $LOG_FILE
    echo "  Prueba: $proof_time seg [$proof_status]" | tee -a $LOG_FILE
    echo "  Verificación: $verify_time seg [$verify_status]" | tee -a $LOG_FILE
    echo "Estado: $([ "$verify_status" == "✅" ] && echo "PASÓ" || echo "FALLÓ")" | tee -a $LOG_FILE

    rm -f $BUILD_DIR/witness_${test_file%.*}.wtns
    rm -f $BUILD_DIR/proof_${test_file%.*}.json
    rm -f $BUILD_DIR/public_${test_file%.*}.json
    rm -f "$TEMP_INPUTS_DIR/$test_file"

done < "$INPUT_FILE"

rmdir "$TEMP_INPUTS_DIR"

# 5. Resultados finales
end_total=$(date +%s.%N)
total_time=$(echo "$end_total - $start_total" | bc)

avg_witness=0
[ $successful_witness -gt 0 ] && avg_witness=$(echo "scale=3; $total_witness / $successful_witness" | bc)

avg_proof=0
[ $successful_proof -gt 0 ] && avg_proof=$(echo "scale=3; $total_proof / $successful_proof" | bc)

avg_verify=0
[ $successful_verify -gt 0 ] && avg_verify=$(echo "scale=3; $total_verify / $successful_verify" | bc)

echo -e "\n[5/5] 📊 RESULTADOS FINALES" | tee -a $LOG_FILE
echo "============================" | tee -a $LOG_FILE
echo "🔢 Total de pruebas: $test_count" | tee -a $LOG_FILE
echo "✅ Pruebas pasadas: $passed" | tee -a $LOG_FILE
echo "❌ Pruebas fallidas: $failed" | tee -a $LOG_FILE
echo "⚠️ Errores de restricción: $constraint_errors" | tee -a $LOG_FILE
echo "⏳ Tiempo total: $total_time seg" | tee -a $LOG_FILE
echo "📈 Promedios (solo casos exitosos):" | tee -a $LOG_FILE
echo "  Generación de witness: $avg_witness seg (en $successful_witness casos)" | tee -a $LOG_FILE
echo "  Generación de prueba: $avg_proof seg (en $successful_proof casos)" | tee -a $LOG_FILE
echo "  Verificación: $avg_verify seg (en $successful_verify casos)" | tee -a $LOG_FILE
echo "============================" | tee -a $LOG_FILE
echo "✅ Benchmark completado" | tee -a $LOG_FILE

exit 0
