#!/bin/bash

export LC_NUMERIC=C
mkdir -p normalizados

# Arrays para control de errores
fallidos=()
procesados=0
total=$(ls *.wav 2>/dev/null | wc -l)

# Si no hay archivos WAV
if [ "$total" -eq 0 ]; then
    echo "⚠️  No se encontraron archivos .wav en este directorio."
    exit 1
fi

# Función para mostrar barra de progreso
mostrar_progreso() {
    local progreso=$1
    local ancho=40
    local completados=$(( progreso * ancho / 100 ))
    local restantes=$(( ancho - completados ))
    local barra=$(printf "%${completados}s" | tr ' ' '█')
    local vacio=$(printf "%${restantes}s" | tr ' ' ' ')
    printf "\r[%s%s] %d%%" "$barra" "$vacio" "$progreso"
}

for file in *.wav; do
    ((procesados++))
    echo -e "\n🎧 Procesando ($procesados/$total): $file"

    INTENSIDAD=-14
    TP=-1.5
    LRA=11

    # Medir loudness
    OUTPUT=$(ffmpeg -hide_banner -i "$file" -af loudnorm=I=$INTENSIDAD:TP=$TP:LRA=$LRA:print_format=json -f null - 2>&1)
    JSON=$(echo "$OUTPUT" | sed -n '/^{/,/}$/p')
    CLEAN_JSON=$(echo "$JSON" | sed -E 's/(-inf|inf|nan)/0/g')

    if [ -z "$CLEAN_JSON" ]; then
        echo "❌ Error: no se pudo extraer JSON válido"
        fallidos+=("$file")
        continue
    fi

    I_VAL=$(echo "$CLEAN_JSON" | jq -r '.input_i // empty')
    TP_VAL=$(echo "$CLEAN_JSON" | jq -r '.input_tp // empty')
    LRA_VAL=$(echo "$CLEAN_JSON" | jq -r '.input_lra // empty')
    THRESH_VAL=$(echo "$CLEAN_JSON" | jq -r '.input_thresh // empty')
    OFFSET_VAL=$(echo "$CLEAN_JSON" | jq -r '.target_offset // empty')

    if [ -z "$I_VAL" ] || [ -z "$TP_VAL" ] || [ -z "$LRA_VAL" ] || [ -z "$THRESH_VAL" ] || [ -z "$OFFSET_VAL" ]; then
        echo "⚠️  Error: valores inválidos en JSON"
        fallidos+=("$file")
        continue
    fi

    echo "   Normalizando..."

    # Barra de progreso durante FFmpeg
    ffmpeg -hide_banner -y -i "$file" \
        -af loudnorm=I=$INTENSIDAD:TP=$TP:LRA=$LRA:measured_I="$I_VAL":measured_TP="$TP_VAL":measured_LRA="$LRA_VAL":measured_thresh="$THRESH_VAL":offset="$OFFSET_VAL":linear=true:print_format=summary \
        -ar 44100 "normalizados/$file" \
        -progress - 2>&1 | while IFS='=' read key value; do
            if [[ "$key" == "out_time_ms" ]]; then
                duracion_total=$(ffprobe -v error -select_streams a:0 -show_entries stream=duration -of csv=p=0 "$file")
                duracion_total_ms=$(awk "BEGIN {printf \"%d\", $duracion_total * 1000000}")
                porcentaje=$(( value * 100 / duracion_total_ms ))
                if [ "$porcentaje" -gt 100 ]; then porcentaje=100; fi
                mostrar_progreso "$porcentaje"
            fi
        done

    # Resultado del proceso
    if [ $? -eq 0 ]; then
        printf "\r✅ Normalizado: %s\n" "$file"
    else
        printf "\r💥 Error al procesar: %s\n" "$file"
        fallidos+=("$file")
    fi
done

# Resumen final
echo
echo "🎵 Proceso completado: $procesados archivos procesados."
if [ ${#fallidos[@]} -gt 0 ]; then
    echo "⚠️  Han fallado ${#fallidos[@]} canciones:"
    for f in "${fallidos[@]}"; do
        echo "   - $f"
    done
else
    echo "✨ Todos los archivos se normalizaron correctamente."
fi
