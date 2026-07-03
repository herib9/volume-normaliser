#!/bin/bash

# ==============================================================================
# Script: quitar_voces.sh
# Descripción: Elimina la voz de todas las canciones (.flac y .wav) que estén
#              en la MISMA carpeta donde está guardado este script, usando
#              Demucs (modelo htdemucs_ft, alta calidad) y deja solo los
#              instrumentales en una carpeta de salida limpia. Muestra una
#              única barra de progreso real por cada canción en vez de las
#              múltiples barras técnicas que imprime Demucs internamente.
# Uso: ./quitar_voces.sh
#      (simplemente colócalo dentro de la carpeta con tus canciones y ejecútalo)
# ==============================================================================

# --- Variables principales ---
# Averiguamos la ruta absoluta de la carpeta donde está este script,
# sin importar desde dónde lo ejecutes, y la usamos como carpeta de origen
CARPETA_ORIGEN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CARPETA_SALIDA="$CARPETA_ORIGEN/instrumentales"  # Carpeta donde guardaremos los resultados finales
CARPETA_TEMPORAL="$CARPETA_ORIGEN/separado_tmp"  # Carpeta temporal donde Demucs escribe sus archivos
MODELO="mdx_extra"      # "htdemucs_ft"          # Modelo de alta calidad (más lento pero mejor separación)

# --- Crear carpetas necesarias si no existen ---
# -p evita que dé error si la carpeta ya existe, y crea carpetas padre si hace falta
mkdir -p "$CARPETA_SALIDA"
mkdir -p "$CARPETA_TEMPORAL"

# --- Comprobar que hay archivos de audio en la carpeta ---
# shopt -s nullglob hace que si no hay archivos que coincidan, el array quede vacío
# en vez de contener el patrón literal (ej. "*.flac" como texto)
shopt -s nullglob
ARCHIVOS=("$CARPETA_ORIGEN"/*.flac "$CARPETA_ORIGEN"/*.wav)
shopt -u nullglob

if [ ${#ARCHIVOS[@]} -eq 0 ]; then
    echo "No se han encontrado archivos .flac o .wav en: $CARPETA_ORIGEN"
    exit 1
fi

TOTAL=${#ARCHIVOS[@]}   # Número total de canciones encontradas
ACTUAL=0                 # Contador para saber por cuál vamos

# --- Función para dibujar una barra de progreso a partir de un porcentaje ---
# Recibe: un número de 0 a 100, y dibuja algo tipo: [####------------] 42%
dibujar_barra_porcentaje() {
    local porcentaje=$1
    local ancho=40   # Longitud de la barra en caracteres

    # Nos aseguramos de que el valor quede siempre entre 0 y 100
    if [ "$porcentaje" -gt 100 ]; then porcentaje=100; fi
    if [ "$porcentaje" -lt 0 ]; then porcentaje=0; fi

    local rellenas=$(( ancho * porcentaje / 100 ))
    local vacias=$(( ancho - rellenas ))

    local barra=""
    for ((i=0; i<rellenas; i++)); do barra="${barra}#"; done
    for ((i=0; i<vacias; i++)); do barra="${barra}-"; done

    # \r vuelve al principio de la línea para que se sobreescriba en vez de
    # imprimir una línea nueva cada vez (efecto barra "en vivo")
    printf "\r  [%s] %3d%%" "$barra" "$porcentaje"
}

echo "Se han encontrado $TOTAL canciones. Empezando proceso con modelo $MODELO..."
echo "----------------------------------------------------------------"

# --- Bucle principal: procesa cada canción una a una ---
for ARCHIVO in "${ARCHIVOS[@]}"; do
    ACTUAL=$((ACTUAL + 1))

    # Extraemos el nombre del archivo sin la ruta (ej: "cancion.flac")
    NOMBRE_ARCHIVO=$(basename "$ARCHIVO")
    # Extraemos el nombre sin extensión (ej: "cancion")
    NOMBRE_SIN_EXT="${NOMBRE_ARCHIVO%.*}"

    echo ""
    echo "[$ACTUAL/$TOTAL] Procesando: $NOMBRE_ARCHIVO"
    dibujar_barra_porcentaje 0

    # --- Variables para leer el progreso real de Demucs ---
    # htdemucs_ft es un "bag" de varios modelos (normalmente 4) que se
    # ejecutan uno tras otro; necesitamos saber cuántos hay y en cuál vamos
    # para poder calcular un progreso GLOBAL combinado y no solo el de uno
    NUM_MODELOS=1        # Se actualizará automáticamente si Demucs indica más
    MODELO_ACTUAL=1       # En qué sub-modelo vamos ahora mismo
    ULTIMO_PORCENTAJE=-1  # Último porcentaje visto, para detectar reinicios
    RESULTADO=0            # Código de salida de Demucs (0 = sin errores)
    LOG_ERRORES=""          # Aquí guardamos cualquier línea que NO sea de progreso,
                             # por si hay que mostrarla en caso de error

    # --- Función que procesa cada "línea" de progreso que vamos detectando ---
    # La separamos en una función para poder llamarla tanto durante la lectura
    # normal como al final, por si queda algo pendiente sin procesar
    procesar_linea_demucs() {
        local LINEA="$1"

        # Si Demucs indica cuántos sub-modelos componen el modelo elegido
        # (ej: "Selected model is a bag of 4 models"), guardamos ese número
        if [[ $LINEA =~ bag\ of\ ([0-9]+)\ models ]]; then
            NUM_MODELOS="${BASH_REMATCH[1]}"
        fi

        # Capturamos el código de salida real de Demucs que imprimimos
        # nosotros mismos al final del comando (ver más abajo)
        if [[ $LINEA =~ ^CODIGO_SALIDA:([0-9]+)$ ]]; then
            RESULTADO="${BASH_REMATCH[1]}"
            return
        fi

        # Si la línea es una barra de progreso interna (ej: " 45%|████...")
        if [[ $LINEA =~ ^[[:space:]]*([0-9]+)%\| ]]; then
            local PORCENTAJE_MODELO="${BASH_REMATCH[1]}"

            # Si el porcentaje baja de golpe respecto al anterior, significa
            # que ha empezado un nuevo sub-modelo (la barra se reinició a 0%)
            if [ "$PORCENTAJE_MODELO" -lt $((ULTIMO_PORCENTAJE - 5)) ]; then
                MODELO_ACTUAL=$((MODELO_ACTUAL + 1))
            fi
            ULTIMO_PORCENTAJE=$PORCENTAJE_MODELO

            # Progreso global = combinamos en qué sub-modelo vamos con el
            # porcentaje del sub-modelo actual, para tener un único 0-100%
            # que representa la canción completa
            local PORCENTAJE_GLOBAL=$(( ((MODELO_ACTUAL - 1) * 100 + PORCENTAJE_MODELO) / NUM_MODELOS ))
            dibujar_barra_porcentaje "$PORCENTAJE_GLOBAL"
        elif [ -n "$LINEA" ]; then
            # Cualquier otra línea que no sea barra de progreso ni nuestro
            # marcador de código de salida es texto real de Demucs (avisos,
            # errores, rutas, etc.) — lo guardamos por si hace falta mostrarlo
            LOG_ERRORES="${LOG_ERRORES}${LINEA}"$'\n'
        fi
    }

    # --- Ejecutar Demucs leyendo su salida en tiempo real, byte a byte ---
    # PYTHONUNBUFFERED=1 -> evita que Python retenga la salida en buffer,
    #                       así recibimos cada actualización al instante
    # 2>&1               -> unimos la salida de error (donde van las barras)
    #                       con la salida normal, para poder leerlo todo junto
    # echo "CODIGO_SALIDA:$?" -> justo después de Demucs, imprimimos su código
    #                       de salida como una línea más, para poder
    #                       capturarlo dentro del bucle de lectura de abajo
    #
    # IMPORTANTE: NO usamos herramientas externas como "tr" o "sed" para
    # convertir los \r en saltos de línea, porque esos comandos almacenan su
    # salida en un buffer interno cuando no escriben directamente a una
    # terminal (typical de tr/sed/awk), y eso hacía que TODO el progreso se
    # quedara "atascado" y solo apareciera de golpe al final (por eso la
    # barra se veía parada en 0% todo el rato). En su lugar, leemos
    # directamente carácter a carácter con el propio "read" de bash, que no
    # tiene ese problema de buffer, y nosotros mismos detectamos cuándo
    # termina cada actualización (al encontrar un \r o un \n)
    BUFFER_LINEA=""
    while IFS= read -r -n 1 -d '' CARACTER; do
        if [[ "$CARACTER" == $'\r' || "$CARACTER" == $'\n' ]]; then
            procesar_linea_demucs "$BUFFER_LINEA"
            BUFFER_LINEA=""
        else
            BUFFER_LINEA+="$CARACTER"
        fi
    done < <(
        PYTHONUNBUFFERED=1 demucs --two-stems=vocals -n "$MODELO" -o "$CARPETA_TEMPORAL" "$ARCHIVO" 2>&1
        echo "CODIGO_SALIDA:$?"
    )
    # Por si queda algo sin procesar al final (sin \r ni \n detrás)
    if [ -n "$BUFFER_LINEA" ]; then
        procesar_linea_demucs "$BUFFER_LINEA"
    fi

    # Dejamos la barra al 100% visualmente al terminar, y saltamos de línea
    dibujar_barra_porcentaje 100
    echo ""

    # Comprobamos si Demucs terminó bien usando el código que capturamos
    # dentro del bucle de lectura de arriba
    if [ "$RESULTADO" -ne 0 ]; then
        echo "  -> ERROR procesando $NOMBRE_ARCHIVO (código $RESULTADO), saltando a la siguiente."
        echo "  -> Mensaje de Demucs:"
        echo "$LOG_ERRORES" | sed 's/^/     /'
        continue
    fi

    # --- Localizar el archivo instrumental generado ---
    # Demucs guarda el resultado en: CARPETA_TEMPORAL/MODELO/NOMBRE_SIN_EXT/no_vocals.wav
    RUTA_INSTRUMENTAL="$CARPETA_TEMPORAL/$MODELO/$NOMBRE_SIN_EXT/no_vocals.wav"

    if [ -f "$RUTA_INSTRUMENTAL" ]; then
        # Movemos y renombramos el instrumental a la carpeta de salida final
        # con un nombre claro: "cancion_instrumental.wav"
        mv "$RUTA_INSTRUMENTAL" "$CARPETA_SALIDA/${NOMBRE_SIN_EXT}_instrumental.wav"
        echo "  -> Instrumental guardado en: $CARPETA_SALIDA/${NOMBRE_SIN_EXT}_instrumental.wav"
    else
        echo "  -> AVISO: no se encontró el archivo instrumental esperado."
    fi

    echo "----------------------------------------------------------------"
done

# --- Limpieza final ---
# Borramos la carpeta temporal completa, incluyendo las voces separadas (vocals.wav)
# que no necesitamos conservar
rm -rf "$CARPETA_TEMPORAL"

echo "Proceso completado. Tienes $TOTAL instrumentales en: $CARPETA_SALIDA"
