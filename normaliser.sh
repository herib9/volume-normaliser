#!/bin/bash

# Forzar uso de punto como separador decimal
export LC_NUMERIC=C

# Crear carpeta de salida
mkdir -p normalizados

# Procesar todos los WAV
for file in *.wav; do
    if [ -f "normalizados/$file" ]; then
        echo "⚠️  Saltando $file, ya existe en ./normalizados"
        continue
  fi
  echo "Procesando: $file"

  # Usar los mismos parámetros en ambas fases
  INTENSIDAD=-14
  TP=-1.5
  LRA=11

  # Paso 1: medir
  OUTPUT=$(ffmpeg -hide_banner -i "$file" -af loudnorm=I=$INTENSIDAD:TP=$TP:LRA=$LRA:print_format=json -f null - 2>&1)

  # Extraer JSON
  JSON=$(echo "$OUTPUT" | sed -n '/{/,$p' | tr -d '\r\n')

  # Obtener valores
  I_VAL=$(echo "$JSON" | jq -r '.input_i' | tr ',' '.')
  TP_VAL=$(echo "$JSON" | jq -r '.input_tp' | tr ',' '.')
  LRA_VAL=$(echo "$JSON" | jq -r '.input_lra' | tr ',' '.')
  THRESH_VAL=$(echo "$JSON" | jq -r '.input_thresh' | tr ',' '.')
  OFFSET_VAL=$(echo "$JSON" | jq -r '.target_offset' | tr ',' '.')

  if [ -z "$I_VAL" ] || [ -z "$TP_VAL" ] || [ -z "$LRA_VAL" ] || [ -z "$THRESH_VAL" ] || [ -z "$OFFSET_VAL" ]; then
    echo "Error: No se pudieron obtener todos los valores para $file"
    continue
  fi

  # Paso 2: aplicar normalización fija (linear=true)
  ffmpeg -i "$file" -af loudnorm=I=$INTENSIDAD:TP=$TP:LRA=$LRA:measured_I="$I_VAL":measured_TP="$TP_VAL":measured_LRA="$LRA_VAL":measured_thresh="$THRESH_VAL":offset="$OFFSET_VAL":linear=true:print_format=summary -ar 44100 "normalizados/$file"

  echo "✅ Normalizado: $file"
done

echo "🎉 Todos los archivos fueron normalizados en ./normalizados"

 # chmod +x normalizar_flac.sh
 # ./normalizar_flac.sh
