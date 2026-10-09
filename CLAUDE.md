# CLAUDE.md — servidor-ia

Este repo describe cómo convertir este PC en un servidor de inferencia local. Tú (Claude Code) eres el ejecutor; Efra supervisa.

## Reglas

- Lee `SPEC.md` completo antes de tocar nada.
- Ejecuta las fases **en orden**. Al final de cada fase entrega el bloque "Reportar al terminar" y **detente** hasta que Efra confirme.
- Idioma: español, Colombia. Respuestas cortas, tablas cuando haya varias cosas que comparar.
- Nunca:
  - montes, formatees o toques el SSD de 1 TB (es el Kubuntu de respaldo);
  - uses `--host 0.0.0.0` en `llama-server`;
  - pases capas a CPU en modo diurno (`-ngl` siempre 99);
  - instales un escritorio gráfico;
  - inventes nombres de repos o archivos GGUF: verifica en Hugging Face y si no existe, repórtalo con alternativas.
- Antes de cualquier `apt upgrade` o reinicio, avisa.
- Si un comando necesita un dato que no tienes (MAC, IP de Tailscale, nombre de interfaz), obténlo con el sistema; no preguntes lo que puedes consultar.

## Estado de fases

Actualiza esta tabla al cerrar cada fase (commit en `main` con mensaje `fase N: <resumen>`).

| Fase | Estado | Fecha | Notas |
| --- | --- | --- | --- |
| 1 Parte A (bootstrap) | pendiente | | |
| 1 Parte B (drivers, CUDA, estructura) | pendiente | | |
| 2 llama.cpp + modelos | pendiente | | |
| 3 systemd + switch | pendiente | | |
| 4 acceso desde el Mac | pendiente | | se ejecuta en el Mac |
| 5 MCP + hooks | pendiente | | se ejecuta en el Mac |
| 6 benchmark A/B | pendiente | | |
| 7 modo híbrido | pendiente | | condicionada a 1–6 |

## Dónde van los reportes

- `reports/fase-N.md`: el bloque "Reportar al terminar" de cada fase, con salidas reales de comandos.
- `reports/bench.md`: resultados de `llama-bench` por modelo y modo.
- Los archivos de `/opt/llm/conf/*.env` y las unidades systemd se copian a `config/` de este repo (sin la API key) para que queden versionados.
