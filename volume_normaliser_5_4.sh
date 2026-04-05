#!/bin/bash
set -o pipefail
export LC_NUMERIC=C

mkdir -p normalizados

fallidos=()
procesados=0
total=0

# Contar archivos de forma segura (maneja espacios en nombres)
for f in *.wav; do
    [ -e "$f" ] && ((total++))
done

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

INTENSIDAD=-14
TP=-1.5
LRA=11

for file in *.wav; do
    [ -e "$file" ] || continue
    ((procesados++))
    echo -e "\n🎧 Procesando ($procesados/$total): $file"

    # === PASADA 1: Medir loudness ===
    OUTPUT=$(ffmpeg -hide_banner -i "$file" \
        -af loudnorm=I=$INTENSIDAD:TP=$TP:LRA=$LRA:print_format=json \
        -f null - 2>&1)

    JSON=$(echo "$OUTPUT" | sed -n '/^{/,/}$/p')
    CLEAN_JSON=$(echo "$JSON" | sed -E 's/(-inf|inf|nan)/0/g')

    if [ -z "$CLEAN_JSON" ]; then
        echo "❌ Error: no se pudo extraer JSON de ffmpeg"
        echo "   Salida recibida: $OUTPUT"
        fallidos+=("$file")
        continue
    fi

    I_VAL=$(echo "$CLEAN_JSON"     | jq -r '.input_i      // empty')
    TP_VAL=$(echo "$CLEAN_JSON"    | jq -r '.input_tp     // empty')
    LRA_VAL=$(echo "$CLEAN_JSON"   | jq -r '.input_lra    // empty')
    THRESH_VAL=$(echo "$CLEAN_JSON"| jq -r '.input_thresh // empty')
    OFFSET_VAL=$(echo "$CLEAN_JSON"| jq -r '.target_offset// empty')

    if [ -z "$I_VAL" ] || [ -z "$TP_VAL" ] || [ -z "$LRA_VAL" ] \
    || [ -z "$THRESH_VAL" ] || [ -z "$OFFSET_VAL" ]; then
        echo "⚠️  Error: valores inválidos en el JSON recibido:"
        echo "$CLEAN_JSON"
        fallidos+=("$file")
        continue
    fi

    echo "   Normalizando..."

    # === PASADA 2: Aplicar normalización ===
    # ffprobe UNA SOLA VEZ antes del pipe
    duracion_total=$(ffprobe -v error -select_streams a:0 \
        -show_entries stream=duration \
        -of csv=p=0 "$file" 2>/dev/null)
    duracion_total_ms=$(awk "BEGIN {printf \"%d\", $duracion_total * 1000000}")

    ffmpeg -hide_banner -y -i "$file" \
        -af loudnorm=I=$INTENSIDAD:TP=$TP:LRA=$LRA:\
measured_I="$I_VAL":measured_TP="$TP_VAL":measured_LRA="$LRA_VAL":\
measured_thresh="$THRESH_VAL":offset="$OFFSET_VAL":linear=true:print_format=summary \
        "normalizados/$file" \
        -progress - 2>&1 \
    | while IFS='=' read -r key value; do
        if [[ "$key" == "out_time_ms" ]]; then
            porcentaje=$(( value * 100 / duracion_total_ms ))
            [ "$porcentaje" -gt 100 ] && porcentaje=100
            mostrar_progreso "$porcentaje"
        fi
    done

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