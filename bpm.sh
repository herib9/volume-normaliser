#!/bin/bash
set -o pipefail
export LC_NUMERIC=C

# === COMPROBAR E INSTALAR DEPENDENCIAS ===
for tool in rubberband ffmpeg; do
    if ! command -v $tool &>/dev/null; then
        echo "⚙️  Instalando $tool..."
        brew install $tool
    fi
done

if ! python3 -c "import librosa" &>/dev/null; then
    echo "⚙️  Instalando librosa..."
    pip3 install librosa
fi

mkdir -p bpm

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

# Preguntar BPM destino antes de empezar
while true; do
    read -rp "🎯 ¿A qué BPM quieres convertir las canciones? " BPM_DESTINO
    if [[ "$BPM_DESTINO" =~ ^[0-9]+([.][0-9]+)?$ ]] && \
       awk "BEGIN {exit !($BPM_DESTINO > 0)}"; then
        break
    fi
    echo "⚠️  Introduce un número válido mayor que 0."
done

echo -e "\n🎵 BPM destino: $BPM_DESTINO"
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

# Función para detectar BPM con librosa
# Los mensajes van a stderr (>&2) para que se muestren en pantalla
# Solo el número va a stdout para ser capturado por la variable
detectar_bpm() {
    local archivo="$1"
    echo "   🔍 Analizando BPM con librosa..." >&2
    resultado=$(python3 -W ignore -c "
import librosa
y, sr = librosa.load('$archivo', sr=None)
tempo, _ = librosa.beat.beat_track(y=y, sr=sr)
print(round(float(tempo), 2))
" 2>/dev/null)
    if [ -n "$resultado" ] && awk "BEGIN {exit !($resultado > 0)}" 2>/dev/null; then
        echo "   ✔️  BPM detectado: $resultado" >&2
        echo "$resultado"
    else
        echo "" 
    fi
}

for file in *.wav; do
    [ -e "$file" ] || continue
    ((procesados++))

    echo -e "\n🎧 Procesando ($procesados/$total): $file"

    # Saltar si ya existe en bpm
    if [ -f "bpm/$file" ]; then
        echo "   ⏭️  Ya existe en la carpeta bpm, omitiendo."
        continue
    fi

    # === DETECTAR O USAR BPM PASADO POR ARGUMENTO ===
    if [ -n "$1" ]; then
        # BPM pasado directamente al ejecutar el script: ./cambiar_bpm.sh 130
        BPM_ORIGINAL="$1"
        echo "   📌 BPM fijado manualmente: $BPM_ORIGINAL"
    else
        # Detectar automáticamente y pedir confirmación
        BPM_DETECTADO=$(detectar_bpm "$file")

        if [ -z "$BPM_DETECTADO" ]; then
            echo "   ❌ No se pudo detectar el BPM."
        fi

        while true; do
            if [ -n "$BPM_DETECTADO" ]; then
                read -rp "   BPM detectado: $BPM_DETECTADO — ¿Es correcto? (Enter para aceptar / escribe otro BPM para corregir): " RESPUESTA
            else
                read -rp "   Introduce el BPM manualmente: " RESPUESTA
            fi

            if [ -z "$RESPUESTA" ] && [ -n "$BPM_DETECTADO" ]; then
                BPM_ORIGINAL="$BPM_DETECTADO"
                break
            fi

            if [[ "$RESPUESTA" =~ ^[0-9]+([.][0-9]+)?$ ]] && \
               awk "BEGIN {exit !($RESPUESTA > 0)}"; then
                BPM_ORIGINAL="$RESPUESTA"
                break
            fi

            echo "   ⚠️  Introduce un número válido mayor que 0."
        done
    fi

    echo "   BPM original confirmado: $BPM_ORIGINAL"

    # === CALCULAR RATIO DE TEMPO ===
    RATIO=$(awk "BEGIN {printf \"%.6f\", $BPM_DESTINO / $BPM_ORIGINAL}")
    echo "   Ratio de tempo: $RATIO"

    # Advertir si el cambio es mayor del 20%
    AVISO=$(awk "BEGIN {diff=$RATIO-1; if(diff<0) diff=-diff; print (diff > 0.20) ? \"si\" : \"no\"}")
    if [ "$AVISO" = "si" ]; then
        echo "   ⚠️  Cambio de tempo superior al 20% — puede afectar levemente a la calidad"
    fi

    echo "   Cambiando tempo..."

    # === APLICAR CAMBIO DE TEMPO ===
    # rubberband con --tempo para cambiar velocidad sin tocar el pitch
    # -c 6 = calidad maxima, --no-transients = mejor para musica
    rubberband \
        --tempo "$RATIO" \
        --pitch 1.0 \
        -c 6 \
        --no-transients \
        "$file" "bpm/$file" 2>/dev/null

    mostrar_progreso 100

    # Resultado del proceso
    if [ $? -eq 0 ]; then
        printf "\r✅ Completado: %s (%.1f BPM → %.1f BPM)\n" \
            "$file" "$BPM_ORIGINAL" "$BPM_DESTINO"
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
    echo "✨ Todos los archivos se procesaron correctamente."
fi
