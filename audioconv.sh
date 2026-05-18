#!/bin/bash
set -o pipefail
export LC_NUMERIC=C

# === COMPROBAR E INSTALAR DEPENDENCIAS ===
if ! command -v ffmpeg &>/dev/null; then
    echo "⚙️  Instalando ffmpeg..."
    brew install ffmpeg
fi

# === PREGUNTAR DIRECCIÓN DE CONVERSIÓN ===
echo "🎵 ¿Qué conversión quieres realizar?"
echo "   1) FLAC → WAV (16 bits / 44100 Hz)"
echo "   2) WAV  → FLAC (16 bits / 44100 Hz)"
echo ""

while true; do
    read -rn 1 -p "Elige una opción (1 o 2): " OPCION
    if [[ "$OPCION" == "1" || "$OPCION" == "2" ]]; then
        break
    fi
    echo "⚠️  Introduce 1 o 2."
done

# === CONFIGURAR SEGÚN OPCIÓN ===
if [ "$OPCION" == "1" ]; then
    EXTENSION_ENTRADA="flac"
    EXTENSION_SALIDA="wav"
    CARPETA_SALIDA="convWav"
    CODEC="-ar 44100 -c:a pcm_s16le"
    LABEL="FLAC → WAV"
else
    EXTENSION_ENTRADA="wav"
    EXTENSION_SALIDA="flac"
    CARPETA_SALIDA="convFlac"
    CODEC="-ar 44100 -sample_fmt s16 -c:a flac -compression_level 8"
    LABEL="WAV → FLAC"
fi

mkdir -p "$CARPETA_SALIDA"

fallidos=()
procesados=0
total=0

# Contar archivos de forma segura (maneja espacios en nombres)
for f in *."$EXTENSION_ENTRADA"; do
    [ -e "$f" ] && ((total++))
done

if [ "$total" -eq 0 ]; then
    echo "⚠️  No se encontraron archivos .$EXTENSION_ENTRADA en este directorio."
    exit 1
fi

echo -e "\n🔄 Conversión: $LABEL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

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

for file in *."$EXTENSION_ENTRADA"; do
    [ -e "$file" ] || continue
    ((procesados++))

    # Nombre del archivo de salida con la nueva extensión
    nombre_salida="${file%.$EXTENSION_ENTRADA}.$EXTENSION_SALIDA"

    echo -e "\n🎧 Procesando ($procesados/$total): $file"

    # Saltar si ya existe en la carpeta de salida
    if [ -f "$CARPETA_SALIDA/$nombre_salida" ]; then
        echo "   ⏭️  Ya existe en $CARPETA_SALIDA, omitiendo."
        continue
    fi

    # Obtener duración del archivo para la barra de progreso
    duracion_total=$(ffprobe -v error -select_streams a:0 \
        -show_entries stream=duration \
        -of csv=p=0 "$file" 2>/dev/null)
    duracion_total_ms=$(awk "BEGIN {printf \"%d\", $duracion_total * 1000000}")

    echo "   Convirtiendo..."

    # === CONVERTIR ===
    ffmpeg -hide_banner -y -i "$file" \
        $CODEC \
        "$CARPETA_SALIDA/$nombre_salida" \
        -progress - 2>&1 \
    | while IFS='=' read -r key value; do
        if [[ "$key" == "out_time_ms" ]]; then
            porcentaje=$(( value * 100 / duracion_total_ms ))
            [ "$porcentaje" -gt 100 ] && porcentaje=100
            mostrar_progreso "$porcentaje"
        fi
    done

    # Resultado del proceso
    if [ $? -eq 0 ]; then
        printf "\r✅ Convertido: %s → %s\n" "$file" "$nombre_salida"
    else
        printf "\r💥 Error al convertir: %s\n" "$file"
        fallidos+=("$file")
    fi
done

# Resumen final
echo
echo "🎵 Proceso completado: $procesados archivos procesados."
if [ ${#fallidos[@]} -gt 0 ]; then
    echo "⚠️  Han fallado ${#fallidos[@]} archivos:"
    for f in "${fallidos[@]}"; do
        echo "   - $f"
    done
else
    echo "✨ Todos los archivos se convirtieron correctamente."
fi
